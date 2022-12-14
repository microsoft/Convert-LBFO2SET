[![Build status](https://ci.appveyor.com/api/projects/status/y6682ir5f5nj28in?svg=true)](https://ci.appveyor.com/project/MSFTCoreNet/convert-lbfo2set)
[![downloads](https://img.shields.io/powershellgallery/dt/Convert-LBFO2SET.svg?label=downloads)](https://www.powershellgallery.com/packages/Convert-LBFO2SET)

# Notice

We are no longer putting new development effort into Convert-LBFO2SET. The purpose of Convert-LBFO2SET was to help people migrate LBFO-based Hyper-V deployments to SET, the recommended solution when using NIC teaming in conjunction with Hyper-V, SDN, S2D, etc., and to bring awareness to SET for those running Windows Server 2016 and 2019.

Now that LBFO-based Hyper-V deployments are significantly down and with Windows Server 2022, and newer, no longer allowing an LBFO NIC to be attached to a Hyper-V vmSwitch we feel this script has served its purpose.

The Convert-LBFO2SET PowerShell module will remain available until [Windows Server 2019 reaches end of mainstream support on 9 January 2024](https://learn.microsoft.com/en-us/lifecycle/products/windows-server-2019). The module will be retired sometime after that date.

Please note that LBFO itself has not been deprecated, nor is it being removed, in Windows. LBFO should be used for "bare metal", meaning no virtual networking (Hyper-V, SDN/HCI, S2D, etc.) is in use, NIC teaming needs. Things such as, network redundancy on a DC, web server, and so on.

Here is some reading material for those who want to learn more about LBFO, SET, and how they relate to virtual networking:

https://aka.ms/vmq2012


https://aka.ms/vmq2012r2

https://aka.ms/vmq2016

https://aka.ms/vmq2019

https://aka.ms/DownWithLBFO


# Overview

For more information, including how to use this tool, please see [the Wiki](https://github.com/microsoft/Convert-LBFO2SET/wiki)

This tool helps you to migrate a LBFO Team into a SET team.  It will also migrate a vSwitch (if added to the LBFO Team)
To a new vSwitch on SET including the host and guest vNICs.

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
