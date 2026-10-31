// Hypervisor.h -- can this iPad run virtual machines (VirtualMac, UTM)? The kernel's own answer, kern.hv_support: 1 on M1/M2 iPads up to iPadOS
// 16.3.1 (Apple took the hypervisor out of the kernel in 16.4); not there on the other chips. Shared by About This iPad (statusbar/StatusBar.x) and
// Settings > Pointer's Hide in Virtual Mac row (macsettings/PointerSettings.x: shown only where VirtualMac can run, 1.7.2 item 22).
#pragma once
#import <sys/types.h>
#import <sys/sysctl.h>

static inline int MSBDHypervisorCapable(void) {
    int hv = 0; size_t len = sizeof(hv);
    return sysctlbyname("kern.hv_support", &hv, &len, NULL, 0) == 0 && hv == 1;
}
