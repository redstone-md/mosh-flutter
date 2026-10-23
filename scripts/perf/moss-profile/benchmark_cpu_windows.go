package main

import "golang.org/x/sys/windows"

func processCPU() int64 {
	var created, exited, kernel, user windows.Filetime
	check(windows.GetProcessTimes(windows.CurrentProcess(), &created, &exited, &kernel, &user))
	ticks := func(t windows.Filetime) int64 {
		return int64(uint64(t.HighDateTime)<<32|uint64(t.LowDateTime)) * 100
	}
	return ticks(kernel) + ticks(user)
}
