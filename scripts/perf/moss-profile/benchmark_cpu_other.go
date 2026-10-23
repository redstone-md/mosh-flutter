//go:build !windows

package main

import "syscall"

func processCPU() int64 {
	var usage syscall.Rusage
	check(syscall.Getrusage(syscall.RUSAGE_SELF, &usage))
	return (int64(usage.Utime.Sec)+int64(usage.Stime.Sec))*1e9 + (int64(usage.Utime.Usec)+int64(usage.Stime.Usec))*1000
}
