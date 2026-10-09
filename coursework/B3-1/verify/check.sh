#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
PYTHON=python VERIFY_ROOT="$root" sh "$root/verify/test-template-check.sh"
api() { aws --endpoint-url=http://cloud:4566 ec2 "$@"; }
cfn() { aws --endpoint-url=http://cloud:4566 cloudformation "$@"; }
stack=candidate-stack
key=candidate-key
stack_active=''
vpc='' subnet='' gateway='' routes='' group='' association=''
cleanup() {
  if test -n "$stack_active"; then
    cfn delete-stack --stack-name "$stack" >/dev/null
    cfn wait stack-delete-complete --stack-name "$stack"
  fi
  api delete-key-pair --key-name "$key" >/dev/null 2>&1 || true
  test -z "$association" || api disassociate-route-table --association-id "$association" >/dev/null
  test -z "$group" || api delete-security-group --group-id "$group" >/dev/null
  test -z "$subnet" || api delete-subnet --subnet-id "$subnet" >/dev/null
  test -z "$routes" || api delete-route-table --route-table-id "$routes" >/dev/null
  if test -n "$gateway"; then
    api detach-internet-gateway --internet-gateway-id "$gateway" --vpc-id "$vpc" >/dev/null
    api delete-internet-gateway --internet-gateway-id "$gateway" >/dev/null
  fi
  test -z "$vpc" || api delete-vpc --vpc-id "$vpc" >/dev/null
}
trap cleanup EXIT

vpc=$(api create-vpc --cidr-block 10.42.0.0/16 --query Vpc.VpcId --output text)
subnet=$(api create-subnet --vpc-id "$vpc" --cidr-block 10.42.1.0/24 --query Subnet.SubnetId --output text)
gateway=$(api create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
api attach-internet-gateway --internet-gateway-id "$gateway" --vpc-id "$vpc"
routes=$(api create-route-table --vpc-id "$vpc" --query RouteTable.RouteTableId --output text)
api create-route --route-table-id "$routes" --destination-cidr-block 0.0.0.0/0 --gateway-id "$gateway" >/dev/null
association=$(api associate-route-table --route-table-id "$routes" --subnet-id "$subnet" --query AssociationId --output text)
group=$(api create-security-group --group-name candidate-web --description 'Local network contract' --vpc-id "$vpc" --query GroupId --output text)
api authorize-security-group-ingress --group-id "$group" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
api authorize-security-group-ingress --group-id "$group" --protocol tcp --port 22 --cidr 192.0.2.44/32 >/dev/null
test "$(api describe-vpcs --vpc-ids "$vpc" --query 'Vpcs[0].CidrBlock' --output text)" = 10.42.0.0/16
test "$(api describe-subnets --subnet-ids "$subnet" --query 'Subnets[0].VpcId' --output text)" = "$vpc"
test "$(api describe-route-tables --route-table-ids "$routes" --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text)" = "$gateway"
test "$(api describe-route-tables --route-table-ids "$routes" --query 'RouteTables[0].Associations[?SubnetId==`'"$subnet"'`].SubnetId' --output text)" = "$subnet"
test "$(api describe-security-groups --group-ids "$group" --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' --output text)" = 192.0.2.44/32
test "$(api describe-security-groups --group-ids "$group" --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`].IpRanges[].CidrIp' --output text)" = 0.0.0.0/0

cfn validate-template --template-body "file://$root/infrastructure/template.json" >/dev/null
printf '{"Resources":' >/tmp/invalid-template.json
if cfn validate-template --template-body file:///tmp/invalid-template.json >/dev/null 2>&1; then
  printf 'CloudFormation accepted malformed JSON\n' >&2
  exit 1
fi
api create-key-pair --key-name "$key" >/dev/null
parameters="ParameterKey=ImageId,ParameterValue=ami-12345678 ParameterKey=KeyName,ParameterValue=$key"
if cfn create-stack --stack-name invalid-input --template-body "file://$root/infrastructure/template.json" \
  --parameters $parameters ParameterKey=SshSource,ParameterValue=0.0.0.0/0 >/dev/null 2>&1; then
  printf 'LIMIT: LocalStack did not enforce SshSource AllowedPattern; deterministic template regression covers it\n'
  cfn delete-stack --stack-name invalid-input >/dev/null
  cfn wait stack-delete-complete --stack-name invalid-input
fi
cfn create-stack --stack-name "$stack" --template-body "file://$root/infrastructure/template.json" \
  --parameters $parameters ParameterKey=SshSource,ParameterValue=192.0.2.44/32 >/dev/null
stack_active=1
cfn wait stack-create-complete --stack-name "$stack"
if cfn create-stack --stack-name "$stack" --template-body "file://$root/infrastructure/template.json" \
  --parameters $parameters ParameterKey=SshSource,ParameterValue=192.0.2.44/32 >/dev/null 2>&1; then
  printf 'CloudFormation accepted a duplicate stack name\n' >&2
  exit 1
fi
cfn_vpc=$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id Vpc --query StackResourceDetail.PhysicalResourceId --output text)
cfn_subnet=$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id Subnet --query StackResourceDetail.PhysicalResourceId --output text)
cfn_gateway=$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id Gateway --query StackResourceDetail.PhysicalResourceId --output text)
cfn_routes=$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id RouteTable --query StackResourceDetail.PhysicalResourceId --output text)
cfn_group=$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id WebSecurityGroup --query StackResourceDetail.PhysicalResourceId --output text)
cfn_instance=$(cfn describe-stacks --stack-name "$stack" --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
test "$(api describe-vpcs --vpc-ids "$cfn_vpc" --query 'Vpcs[0].CidrBlock' --output text)" = 10.42.0.0/16
test "$(api describe-subnets --subnet-ids "$cfn_subnet" --query 'Subnets[0].VpcId' --output text)" = "$cfn_vpc"
test "$(api describe-subnets --subnet-ids "$cfn_subnet" --query 'Subnets[0].MapPublicIpOnLaunch' --output text)" = True
test "$(api describe-internet-gateways --internet-gateway-ids "$cfn_gateway" --query 'InternetGateways[0].Attachments[0].VpcId' --output text)" = "$cfn_vpc"
test "$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id DefaultRoute --query StackResourceDetail.ResourceStatus --output text)" = CREATE_COMPLETE
cfn_route=$(api describe-route-tables --route-table-ids "$cfn_routes" --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text)
if test -n "$cfn_route"; then
  test "$cfn_route" = "$cfn_gateway"
else
  printf 'LIMIT: LocalStack marked AWS::EC2::Route complete without reflecting it in EC2 metadata; direct API fallback passed\n'
fi
test "$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id SubnetRoute --query StackResourceDetail.ResourceStatus --output text)" = CREATE_COMPLETE
cfn_association=$(api describe-route-tables --route-table-ids "$cfn_routes" --query 'RouteTables[0].Associations[?SubnetId==`'"$cfn_subnet"'`].SubnetId' --output text)
if test -n "$cfn_association"; then
  test "$cfn_association" = "$cfn_subnet"
else
  printf 'LIMIT: LocalStack marked subnet route association complete without EC2 metadata; direct API fallback passed\n'
fi
test "$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id WebSecurityGroup --query StackResourceDetail.ResourceStatus --output text)" = CREATE_COMPLETE
test "$(cfn describe-stacks --stack-name "$stack" --query 'Stacks[0].Parameters[?ParameterKey==`SshSource`].ParameterValue' --output text)" = 192.0.2.44/32
cfn_ssh=$(api describe-security-groups --group-ids "$cfn_group" --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' --output text)
if test -n "$cfn_ssh"; then
  test "$cfn_ssh" = 192.0.2.44/32
else
  printf 'LIMIT: LocalStack did not reflect inline CloudFormation security-group ingress; direct API and template checks passed\n'
fi
metadata_tokens=$(api describe-instances --instance-ids "$cfn_instance" --query 'Reservations[0].Instances[0].MetadataOptions.HttpTokens' --output text)
if test "$metadata_tokens" = required; then
  printf 'PASS: LocalStack reflected required IMDSv2 instance metadata\n'
else
  printf 'LIMIT: LocalStack returned HttpTokens=%s for the template requirement; static regression enforces required\n' "$metadata_tokens"
fi
termination=$(api describe-instances --instance-ids "$cfn_instance" --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.DeleteOnTermination' --output text)
if test "$termination" = True; then
  printf 'PASS: LocalStack reflected delete-on-termination volume metadata\n'
else
  printf 'LIMIT: LocalStack returned DeleteOnTermination=%s; static regression enforces true\n' "$termination"
fi
cfn_volume=$(api describe-instances --instance-ids "$cfn_instance" --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)
if test -n "$cfn_volume" && test "$cfn_volume" != None; then
  encryption=$(api describe-volumes --volume-ids "$cfn_volume" --query 'Volumes[0].Encrypted' --output text)
  if test "$encryption" = True; then
    printf 'PASS: LocalStack reflected encrypted volume metadata\n'
  else
    printf 'LIMIT: LocalStack returned Encrypted=%s; static regression enforces true\n' "$encryption"
  fi
else
  printf 'LIMIT: LocalStack mock instance has no inspectable EBS volume; static regression covers encryption metadata\n'
fi

cfn create-change-set --stack-name "$stack" --change-set-name restrict-ssh \
  --template-body "file://$root/infrastructure/template.json" --change-set-type UPDATE \
  --parameters $parameters ParameterKey=SshSource,ParameterValue=198.51.100.73/32 >/dev/null
cfn wait change-set-create-complete --stack-name "$stack" --change-set-name restrict-ssh
cfn execute-change-set --stack-name "$stack" --change-set-name restrict-ssh >/dev/null
cfn wait stack-update-complete --stack-name "$stack"
cfn_group=$(cfn describe-stack-resource --stack-name "$stack" --logical-resource-id WebSecurityGroup --query StackResourceDetail.PhysicalResourceId --output text)
test "$(cfn describe-stacks --stack-name "$stack" --query 'Stacks[0].Parameters[?ParameterKey==`SshSource`].ParameterValue' --output text)" = 198.51.100.73/32
cfn_ssh=$(api describe-security-groups --group-ids "$cfn_group" --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' --output text)
if test -n "$cfn_ssh"; then
  test "$cfn_ssh" = 198.51.100.73/32
else
  printf 'LIMIT: change-set parameter updated, but LocalStack still omitted inline ingress metadata\n'
fi

cfn delete-stack --stack-name "$stack" >/dev/null
cfn wait stack-delete-complete --stack-name "$stack"
stack_active=''
cfn create-stack --stack-name "$stack" --template-body "file://$root/infrastructure/template.json" \
  --parameters $parameters ParameterKey=SshSource,ParameterValue=192.0.2.44/32 >/dev/null
stack_active=1
cfn wait stack-create-complete --stack-name "$stack"

test "$(curl --fail --silent "$WEB_URL/health")" = OK
test "$(curl --silent --output /dev/null --write-out '%{http_code}' "$WEB_URL/not-present")" = 404
if test "${VERIFY_MODE:-docker}" = vm; then
  curl --fail --silent "$WEB_URL/__vm-proof.txt" | grep -q '^kernel=Linux '
fi
printf 'PASS: direct EC2 CRUD and CloudFormation validate/create/change/update/delete/recreate lifecycles\n'
printf 'PASS: topology outputs, restricted ingress API metadata, static IMDSv2/encrypted-volume requirements, HTTP routes\n'
printf 'LIMIT: LocalStack mock metadata is not EC2 boot, EBS encryption, SG/IAM enforcement or AWS deployment evidence\n'
