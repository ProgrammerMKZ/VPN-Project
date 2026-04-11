"""
AmneziaWG IP Rotation Lambda

Rotates Elastic IPs for VPN servers every 24h with zero downtime.
- Associates new EIP before releasing old one (implicit disassociation)
- Rolls back EIP allocation on association failure
- Enumerates actual S3 client keys instead of hardcoded counts
- Includes PresharedKey and obfuscation params in regenerated configs
- Updates server IP in SSM after successful rotation
"""

import json
import logging
import os
import re

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
s3 = boto3.client("s3")
ssm = boto3.client("ssm")

PROJECT_NAME = os.environ["PROJECT_NAME"]
CONFIG_BUCKET = os.environ["CONFIG_BUCKET"]
SERVER_COUNT = int(os.environ["SERVER_COUNT"])
VPN_PORT = os.environ["VPN_PORT"]
VPN_SUBNET = os.environ["VPN_SUBNET"]
DNS_SERVERS = os.environ["DNS_SERVERS"]

AWG_PARAMS = {
    "Jc": os.environ["AWG_JC"],
    "Jmin": os.environ["AWG_JMIN"],
    "Jmax": os.environ["AWG_JMAX"],
    "S1": os.environ["AWG_S1"],
    "S2": os.environ["AWG_S2"],
    "H1": os.environ["AWG_H1"],
    "H2": os.environ["AWG_H2"],
    "H3": os.environ["AWG_H3"],
    "H4": os.environ["AWG_H4"],
}


def lambda_handler(event, context):
    logger.info("Starting IP rotation for %d server(s)", SERVER_COUNT)

    results = []
    for server_idx in range(SERVER_COUNT):
        try:
            result = rotate_server(server_idx)
            results.append(result)
        except Exception:
            logger.exception("Failed to rotate server %d", server_idx)
            results.append({"server": server_idx, "status": "FAILED"})

    logger.info("Rotation results: %s", json.dumps(results))
    return {"statusCode": 200, "results": results}


def rotate_server(server_idx: int) -> dict:
    """Rotate the EIP for a single server with zero-downtime semantics."""
    instance_id = find_instance_by_tag(server_idx)

    old_eip_info = get_current_eip(instance_id)
    old_allocation_id = old_eip_info["AllocationId"] if old_eip_info else None
    old_ip = old_eip_info["PublicIp"] if old_eip_info else None

    logger.info(
        "Server %d (%s): current EIP %s (%s)",
        server_idx, instance_id, old_ip, old_allocation_id,
    )

    new_allocation_id = None
    try:
        alloc_resp = ec2.allocate_address(
            Domain="vpc",
            TagSpecifications=[{
                "ResourceType": "elastic-ip",
                "Tags": [
                    {"Key": "Service", "Value": "amnezia-vpn"},
                    {"Key": "Name", "Value": f"{PROJECT_NAME}-eip-{server_idx}"},
                    {"Key": "ServerIndex", "Value": str(server_idx)},
                ],
            }],
        )
        new_allocation_id = alloc_resp["AllocationId"]
        new_ip = alloc_resp["PublicIp"]
        logger.info("Allocated new EIP: %s (%s)", new_ip, new_allocation_id)

        # Zero-downtime: associate new EIP first (implicitly disassociates old)
        ec2.associate_address(
            InstanceId=instance_id,
            AllocationId=new_allocation_id,
            AllowReassociation=True,
        )
        logger.info("Associated new EIP %s with %s", new_ip, instance_id)

    except Exception:
        # EIP leak rollback: release newly allocated EIP if association failed
        if new_allocation_id:
            logger.warning(
                "Association failed — releasing leaked EIP %s", new_allocation_id
            )
            try:
                ec2.release_address(AllocationId=new_allocation_id)
            except ClientError:
                logger.exception(
                    "Failed to release leaked EIP %s", new_allocation_id
                )
        raise

    # Release old EIP only after successful association
    if old_allocation_id:
        try:
            ec2.release_address(AllocationId=old_allocation_id)
            logger.info("Released old EIP: %s (%s)", old_ip, old_allocation_id)
        except ClientError:
            logger.exception(
                "Failed to release old EIP %s (non-fatal)", old_allocation_id
            )

    # Update SSM with new IP
    ssm.put_parameter(
        Name=f"/{PROJECT_NAME}/server/{server_idx}/public_ip",
        Value=new_ip,
        Type="String",
        Overwrite=True,
    )

    # Regenerate client configs with new server IP
    regenerate_client_configs(server_idx, new_ip)

    return {
        "server": server_idx,
        "status": "OK",
        "old_ip": old_ip,
        "new_ip": new_ip,
    }


def get_current_eip(instance_id: str) -> dict | None:
    """Get the currently associated EIP for an instance."""
    resp = ec2.describe_addresses(
        Filters=[{"Name": "instance-id", "Values": [instance_id]}]
    )
    addresses = resp.get("Addresses", [])
    return addresses[0] if addresses else None


def find_instance_by_tag(server_idx: int) -> str:
    """Find instance ID by ServerIndex tag."""
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Service", "Values": ["amnezia-vpn"]},
            {"Name": "tag:ServerIndex", "Values": [str(server_idx)]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    for reservation in resp["Reservations"]:
        for instance in reservation["Instances"]:
            return instance["InstanceId"]
    raise RuntimeError(f"No running instance found for server index {server_idx}")


def offset_ip(base_ip: str, offset: int) -> str:
    """Add an integer offset to an IPv4 address, rolling over octets correctly."""
    parts = list(map(int, base_ip.split(".")))
    ip_int = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    ip_int += offset
    return f"{(ip_int >> 24) & 0xFF}.{(ip_int >> 16) & 0xFF}.{(ip_int >> 8) & 0xFF}.{ip_int & 0xFF}"


def get_ssm_param(name: str) -> str | None:
    """Fetch an SSM parameter, returning None if not found."""
    try:
        resp = ssm.get_parameter(Name=name, WithDecryption=True)
        return resp["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        return None


def get_ssm_params(names: list[str]) -> dict[str, str]:
    """Fetch multiple SSM parameters in a single API call."""
    resp = ssm.get_parameters(Names=names, WithDecryption=True)
    return {p["Name"]: p["Value"] for p in resp.get("Parameters", [])}


def enumerate_clients(server_idx: int) -> list[int]:
    """
    Discover actual client indices by listing S3 keys.
    Looks for keys like: server-{idx}/keys/client{N}_private.key
    """
    prefix = f"server-{server_idx}/keys/"
    client_indices = set()
    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=CONFIG_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            match = re.search(r"client(\d+)_private\.key$", obj["Key"])
            if match:
                client_indices.add(int(match.group(1)))

    return sorted(client_indices)


def s3_get_text(key: str) -> str:
    """Read a text object from the config bucket."""
    resp = s3.get_object(Bucket=CONFIG_BUCKET, Key=key)
    return resp["Body"].read().decode("utf-8").strip()


def regenerate_client_configs(server_idx: int, new_ip: str):
    """Regenerate all client configs for a server with the new IP."""
    client_indices = enumerate_clients(server_idx)
    logger.info(
        "Server %d: regenerating configs for %d clients: %s",
        server_idx, len(client_indices), client_indices,
    )

    param_names = [
        f"/{PROJECT_NAME}/server/{server_idx}/public_key",
        f"/{PROJECT_NAME}/server/{server_idx}/listen_port",
    ]
    params = get_ssm_params(param_names)

    server_public_key = params.get(param_names[0])
    if not server_public_key:
        raise RuntimeError(
            f"Server {server_idx} public key not found in SSM"
        )

    listen_port = params.get(param_names[1]) or VPN_PORT

    vpn_base = VPN_SUBNET.split("/")[0]
    vpn_mask = VPN_SUBNET.split("/")[1]

    for client_idx in client_indices:
        try:
            key_prefix = f"server-{server_idx}/keys"
            client_private_key = s3_get_text(
                f"{key_prefix}/client{client_idx}_private.key"
            )
            client_address = f"{offset_ip(vpn_base, client_idx + 1)}/{vpn_mask}"

            # Fetch PresharedKey — initial generation creates these
            psk = None
            try:
                psk = s3_get_text(f"{key_prefix}/client{client_idx}_psk.key")
            except ClientError as e:
                if e.response["Error"]["Code"] == "NoSuchKey":
                    logger.warning(
                        "No PSK for client %d on server %d", client_idx, server_idx
                    )
                else:
                    raise

            awg_lines = "\n".join(
                f"{k} = {v}" for k, v in AWG_PARAMS.items()
            )

            peer_lines = [
                f"PublicKey = {server_public_key}",
                f"Endpoint = {new_ip}:{listen_port}",
                "AllowedIPs = 0.0.0.0/0",
                "PersistentKeepalive = 25",
            ]
            if psk:
                peer_lines.append(f"PresharedKey = {psk}")

            config = (
                f"[Interface]\n"
                f"PrivateKey = {client_private_key}\n"
                f"Address = {client_address}\n"
                f"DNS = {DNS_SERVERS}\n"
                f"{awg_lines}\n"
                f"\n"
                f"[Peer]\n"
                + "\n".join(peer_lines)
                + "\n"
            )

            s3.put_object(
                Bucket=CONFIG_BUCKET,
                Key=f"server-{server_idx}/configs/client{client_idx}.conf",
                Body=config.encode("utf-8"),
                ServerSideEncryption="aws:kms",
            )
        except Exception:
            logger.exception(
                "Failed to regenerate config for client %d on server %d",
                client_idx, server_idx,
            )

    logger.info("Server %d: config regeneration complete", server_idx)
