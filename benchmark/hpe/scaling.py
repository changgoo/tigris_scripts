import numpy as np
import matplotlib.pyplot as plt
import os

def get_zcs(mb="mb64",physics="mhd",CC="icpx",machine="hpe"):
    n = np.array([1, 2, 4, 8, 16, 32, 64, 96, 128, 144])
    scratch_dir = f"/home/users/e89961/{machine}/blast-scaling-{CC}"
    zcs = []
    ntask = []
    for n_ in n:
        fname = os.path.join(scratch_dir, f"{physics}-{mb}_n{n_}", "out.txt")
        if os.path.exists(fname) == False:
            print(fname, "doesn't exist")
            continue
        with open(fname, "r") as f:
            lines = f.readlines()
        zcs.append(eval(lines[-1].split("=")[-1].strip()))
        ntask.append(n_)
    zcs = np.array(zcs)
    ntask = np.array(ntask)
    return ntask, zcs


if __name__=="__main__":
    fig,axes = plt.subplots(1,2,figsize=(10,5),
                        sharey="row", sharex=True, constrained_layout=True)

    mb="mb64"
    for ax, physics in zip(axes,  ["hydro", "mhd"]):
        plt.sca(ax)
        plt.title(f"{mb}, {physics}")
        for machine, CC in zip( ["6960P_32GB","6960P_64GB"],["icpx", "icpx"]):
            n, zcs = get_zcs(mb=mb,CC=CC,physics=physics,machine=machine)
            if len(zcs) == 0:
                continue
            print(n, zcs/n)
            plt.plot(n, zcs/n, 'o-', label=f"{machine},{CC}")
 
        plt.xscale("log")
 
        plt.ylabel("zone cycles/second/core")
        plt.xlabel("number of cores")
#    fig,axes = plt.subplots(1,2,figsize=(10,5),
#                            sharey="row", sharex=True, constrained_layout=True)
#    physics="mhd"
#    mb="mb64"
#    for ax, machine in zip(axes,  ["6960P_32GB","6960P_64GB"]):
#        plt.sca(ax)
#        plt.title(f"{mb}, {machine}")
#        for CC in ["icpx"]:
#            n, zcs = get_zcs(mb=mb,CC=CC,physics=physics,machine=machine)
#            if len(zcs) == 0:
#                print("nodata")
#                continue
#            print(n, zcs/n)
#            plt.plot(n, zcs/n, 'o-', label=CC)
# 
#        plt.xscale("log")
# 
#        plt.ylabel("zone cycles/second/core")
#        plt.xlabel("number of cores")
    plt.legend()
    plt.savefig(f"blast-scaling.png")
