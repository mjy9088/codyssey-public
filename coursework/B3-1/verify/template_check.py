# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
import sys
from pathlib import Path

template_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("infrastructure/template.json")
policy_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("infrastructure/deployer-policy.json")
template = json.loads(template_path.read_text(encoding="utf-8"))
resources = template["Resources"]
assert resources["Subnet"]["Properties"]["VpcId"] == {"Ref": "Vpc"}
assert resources["DefaultRoute"]["Properties"]["DestinationCidrBlock"] == "0.0.0.0/0"
assert resources["DefaultRoute"]["Properties"]["GatewayId"] == {"Ref": "Gateway"}
ingress = resources["WebSecurityGroup"]["Properties"]["SecurityGroupIngress"]
assert len(ingress) == 2
assert ingress[0] == {"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "CidrIp": "0.0.0.0/0"}
assert ingress[1] == {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "CidrIp": {"Ref": "SshSource"}}
assert "Default" not in template["Parameters"]["ImageId"]
assert template["Parameters"]["SshSource"]["AllowedPattern"] == "([0-9]{1,3}\\.){3}[0-9]{1,3}/32"
instance = resources["WebInstance"]["Properties"]
assert instance["MetadataOptions"]["HttpTokens"] == "required"
root_volume = instance["BlockDeviceMappings"][0]["Ebs"]
assert root_volume["Encrypted"] is True
assert root_volume["DeleteOnTermination"] is True
assert template["Outputs"]["InstanceId"]["Value"] == {"Ref": "WebInstance"}
assert template["Outputs"]["HealthUrl"]["Value"] == {
    "Fn::Sub": "http://${WebInstance.PublicIp}/health"
}
policy = json.loads(policy_path.read_text(encoding="utf-8"))
for statement in policy["Statement"]:
    assert all(action != "*" and not action.endswith(":*") for action in statement["Action"])
    assert all(action.startswith(("ec2:", "cloudformation:")) for action in statement["Action"])
    if statement["Sid"] == "ManageOwnedNetworkResources":
        assert statement["Condition"]["StringEquals"]["ec2:ResourceTag/Project"] == "network-candidate"
print("PASS: topology, ingress, metadata, storage and IAM review invariants")
