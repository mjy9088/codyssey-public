# Azure Cleanup Procedure

This is a procedure, not a claim that a cloud run occurred. Record results only during an authorized
deployment. Any required submitted cleanup record is an exception to the normal policy of keeping run
evidence out of Git.

1. In `infrastructure/deployment/`, refresh and review `terraform plan -destroy -out=destroy.tfplan`.
2. Explicitly apply that saved destroy plan with the restricted deployer.
3. In Azure, confirm deletion of the VM, managed OS disk, NIC, Standard public IP, NSG, route and route
   table, subnet, and VNet. Investigate only owned remnants; do not delete unrelated resources.
4. Check for resources created outside this configuration, locks, policy-created resources, retained
   disks or snapshots, and delayed cost records.
5. The authorized role manager, not the restricted deployer, reviews and destroys the bootstrap root to
   remove the role assignment, custom role, and dedicated resource group.
6. Confirm the intended Microsoft Entra principal no longer has the custom assignment and review Azure
   cost data. Terraform mocks and an empty local state cannot prove cleanup or absence of charges.

Never automate real-cloud destroy in the local verifier. Protect and then dispose of real state and
saved plans according to the approved state-storage procedure; none belongs in this repository.
