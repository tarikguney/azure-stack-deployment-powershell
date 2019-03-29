# Azure Stack Deployment Automation

We needed something like this when working with Azure Stack, an on-prem version of Azure, so I developed this script that provisions an environment including network, vm, disk, etc. based on the given VM image that it uploads to the blob storage on Azure Stack automatically. Check out the script to see all the steps it accomplishes for you. It also logs into Azure Stack automatically to be able to perform all these operations.

Make sure you modified all the variables at the top of the file before using it. You need some familiarity with Azure environment to be able to understand what all those variables are for. The rest is pretty straightforward.
