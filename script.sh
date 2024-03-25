#/bin/bash
mkdir -p logs
verbose=1
{
echo "[*] Command ran:`if [ $EUID = 0 ]; then echo " sudo"; fi` ./semaphorin.sh $@"
os=$(uname)
oscheck=$(uname)
version="$1"
dir="$(pwd)/"
bin="$(pwd)/$(uname)"
sshtars="$(pwd)/sshtars"
echo "semaphorin | Version 1.0"
echo "Written by y08wilm and Mineek | Some code and ramdisk from Nathan"
echo ""
sudo mount -uw /
max_args=1
arg_count=0
print_help() {
    cat << EOF
Usage: $0 [VERSION]... [OPTION]...
iOS 7.0.1-9.2.1 seprmvr64, downgrade& jailbreak tool for checkm8 devices
Examples:
    $0 7.1.2 --dfuhelper
    $0 7.1.2 --restore
    $0 7.1.2 --boot

Main operation mode:
    --help              Print this help
    --ramdisk           Download& enter ramdisk
    --dump-blobs        Self explanatory
    --ssh               Tries to connect to ssh over usb interface to the connected device
    --restore           Wipe device and downgrade ios
    --boot              Don't enter ramdisk or wipe device, just boot
    --clean             Delete all the created boot files for your device

The iOS version argument should be the iOS version you are downgrading to.
EOF
}

parse_opt() {
    case "$1" in
        --)
            no_more_opts=1
            ;;
        --ramdisk)
            ramdisk=1
            ;;
        --dump-blobs)
            dump_blobs=1
            ;;
        --ssh)
            _kill_if_running iproxy
            "$bin"/iproxy 2222 22 &
            ssh -p2222 root@localhost
            exit 0
            ;;
        --restore)
            restore=1
            ;;
        --boot)
            boot=1
            ;;
        --clean)
            rm -rf "$dir"/$deviceid/$1/
            rm -rf "$dir"/ramdisk/
            exit 0
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "[-] Unknown option $1. Use $0 --help for help."
            exit 1;
    esac
}

parse_arg() {
    arg_count=$((arg_count + 1))
    case "$1" in
        clean)
            rm -rf "$dir"/$deviceid/$1/
            rm -rf "$dir"/ramdisk/
            exit 0
            ;;
        ssh)
            _kill_if_running iproxy
            "$bin"/iproxy 2222 22 &
            ssh -p2222 root@localhost
            exit 0
            ;;
        *)
            ;;
    esac
}
parse_cmdline() {
    if [ -z "$1" ]; then
        print_help
        exit 0
    fi
    hit=0
    for arg in $@; do
        if [[ "$arg" == --* ]] && [ -z "$no_more_opts" ]; then
            parse_opt "$arg";
            hit=1
        elif [ "$arg_count" -lt "$max_args" ]; then
            parse_arg "$arg";
        else
            echo "[-] Too many arguments. Use $0 --help for help.";
            exit 1;
        fi
    done
    if [[ "$hit" == 0 ]]; then
        print_help
        exit 0
    fi
}
_wait_for_dfu() {
    if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); then
        echo "[*] Waiting for device in DFU mode"
    fi
    
    while ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); do
        sleep 1
    done
}
_download_ramdisk_boot_files() {
    ipswurl=$(curl -k -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$bin"/jq '.firmwares | .[] | select(.version=="'$3'")' | "$bin"/jq -s '.[0] | .url' --raw-output)
    rm -rf BuildManifest.plist
    mkdir -p "$dir"/ramdisk
    rm -rf work
    mkdir work
    cd work
    "$bin"/img4tool -e -s "$dir"/other/shsh/"${check}".shsh -m IM4M
    if [ ! -e "$dir"/ramdisk/ramdisk.img4 ]; then
        "$bin"/pzb -g BuildManifest.plist "$ipswurl"
        if [ ! -e "$dir"/ramdisk/kernelcache.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1) "$ipswurl"
            if [[ "$3" == "7."* || "$3" == "8."* || "$3" == "9."* ]]; then
                fn="$(awk "/""$2""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)"
                ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
                "$bin"/img4 -i $fn -o "$dir"/ramdisk/kcache.raw -k $ivkey
                "$bin"/img4 -i $fn -o "$dir"/ramdisk/kernelcache.dec -k $ivkey -D
                pyimg4 im4p extract -i $fn -o "$dir"/ramdisk/kernelcache_pyimg4.dec --iv ${ivkey:0:32} --key ${ivkey:32} --extra "$dir"/ramdisk/kpp.bin
            else
                "$bin"/img4 -i $(awk "/""$2""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1) -o "$dir"/ramdisk/kcache.raw
                "$bin"/img4 -i $(awk "/""$2""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1) -o "$dir"/ramdisk/kernelcache.dec -D
            fi
        fi
        if [ ! -e "$dir"/ramdisk/iBSS.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1) "$ipswurl"
            fn="$(awk "/""$2""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/ramdisk/iBSS.dec -k $ivkey
        fi
        if [ ! -e "$dir"/ramdisk/iBEC.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1) "$ipswurl"
            fn="$(awk "/""$2""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/ramdisk/iBEC.dec -k $ivkey
        fi
        if [ ! -e "$dir"/ramdisk/DeviceTree.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1) "$ipswurl"
            if [[ "$3" == "7."* || "$3" == "8."* || "$3" == "9."* ]]; then
                fn="$(awk "/""$2""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]all_flash.*production[/]//' | sed 's/Firmware[/]all_flash[/]//')"
                ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
                "$bin"/img4 -i $fn -o "$dir"/ramdisk/DeviceTree.dec -k $ivkey
            else
                mv $(awk "/""$2""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]all_flash.*production[/]//' | sed 's/Firmware[/]all_flash[/]//') "$dir"/ramdisk/DeviceTree.dec
            fi
        fi
        if [ ! -e "$dir"/ramdisk/RestoreRamDisk.dmg ]; then
            "$bin"/pzb -g "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" "$ipswurl"
            if [[ "$3" == "7."* || "$3" == "8."* || "$3" == "9."* ]]; then
                fn="$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)"
                ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
                "$bin"/img4 -i $fn -o "$dir"/ramdisk/RestoreRamDisk.dmg -k $ivkey
            else
                "$bin"/img4 -i "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" -o "$dir"/ramdisk/RestoreRamDisk.dmg
            fi
        fi
        if [[ "$3" == "12."* ]]; then
            if [ ! -e "$dir"/ramdisk/trustcache.img4 ]; then
                "$bin"/pzb -g Firmware/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache "$ipswurl"
                 mv "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache "$dir"/ramdisk/trustcache.im4p
            fi
        fi
        rm -rf BuildManifest.plist
        if [[ "$3" == "7."* || "$3" == "8."* || "$3" == "9."* ]]; then
            if [[ "$3" == "9."* ]]; then
                hdiutil resize -size 80M "$dir"/ramdisk/RestoreRamDisk.dmg
            else
                hdiutil resize -size 60M "$dir"/ramdisk/RestoreRamDisk.dmg
            fi
            hdiutil attach -mountpoint /tmp/ramdisk "$dir"/ramdisk/RestoreRamDisk.dmg
            sudo diskutil enableOwnership /tmp/ramdisk
            sudo "$bin"/gnutar -xvf "$sshtars"/ssh_apfs.tar -C /tmp/ramdisk
            hdiutil detach /tmp/ramdisk
            "$bin"/img4tool -c "$dir"/ramdisk/ramdisk.im4p -t rdsk "$dir"/ramdisk/RestoreRamDisk.dmg
            "$bin"/img4tool -c "$dir"/ramdisk/ramdisk.img4 -p "$dir"/ramdisk/ramdisk.im4p -m IM4M
            if [[ "$3" == "9."* ]]; then
                "$bin"/iBoot64Patcher "$dir"/ramdisk/iBSS.dec "$dir"/ramdisk/iBSS.patched
                "$bin"/iBoot64Patcher "$dir"/ramdisk/iBEC.dec "$dir"/ramdisk/iBEC.patched -b "amfi=0xff cs_enforcement_disable=1 -v rd=md0 nand-enable-reformat=1 -progress"
            else
                "$bin"/ipatcher "$dir"/ramdisk/iBSS.dec "$dir"/ramdisk/iBSS.patched
                "$bin"/ipatcher "$dir"/ramdisk/iBEC.dec "$dir"/ramdisk/iBEC.patched -b "amfi=0xff cs_enforcement_disable=1 -v rd=md0 nand-enable-reformat=1 -progress"
            fi
            "$bin"/img4 -i "$dir"/ramdisk/iBSS.patched -o "$dir"/ramdisk/iBSS.img4 -M IM4M -A -T ibss
            "$bin"/img4 -i "$dir"/ramdisk/iBEC.patched -o "$dir"/ramdisk/iBEC.img4 -M IM4M -A -T ibec
            "$bin"/img4 -i "$dir"/ramdisk/kernelcache.dec -o "$dir"/ramdisk/kernelcache.img4 -M IM4M -T rkrn
            "$bin"/img4 -i "$dir"/ramdisk/devicetree.dec -o "$dir"/ramdisk/devicetree.img4 -A -M IM4M -T rdtr
        else
            hdiutil resize -size 120M "$dir"/ramdisk/RestoreRamDisk.dmg
            hdiutil attach -mountpoint /tmp/ramdisk "$dir"/ramdisk/RestoreRamDisk.dmg
            sudo diskutil enableOwnership /tmp/ramdisk
            sudo "$bin"/gnutar -xvf "$sshtars"/ssh_apfs.tar -C /tmp/ramdisk
            hdiutil detach /tmp/ramdisk
            "$bin"/img4 -i "$dir"/ramdisk/RestoreRamDisk.dmg -o "$dir"/ramdisk/ramdisk.img4 -M IM4M -A -T rdsk
            "$bin"/iBoot64Patcher "$dir"/ramdisk/iBSS.dec "$dir"/ramdisk/iBSS.patched
            "$bin"/iBoot64Patcher "$dir"/ramdisk/iBEC.dec "$dir"/ramdisk/iBEC.patched -b "amfi=0xff cs_enforcement_disable=1 -v rd=md0 nand-enable-reformat=1 -restore -progress" -n
            "$bin"/img4 -i "$dir"/ramdisk/iBSS.patched -o "$dir"/ramdisk/iBSS.img4 -M IM4M -A -T ibss
            "$bin"/img4 -i "$dir"/ramdisk/iBEC.patched -o "$dir"/ramdisk/iBEC.img4 -M IM4M -A -T ibec
            "$bin"/Kernel64Patcher2 "$dir"/ramdisk/kcache.raw "$dir"/ramdisk/kcache2.patched -a
            "$bin"/kerneldiff "$dir"/ramdisk/kcache.raw "$dir"/ramdisk/kcache2.patched "$dir"/ramdisk/kc.bpatch
            "$bin"/img4 -i "$dir"/ramdisk/kernelcache.dec -o "$dir"/ramdisk/kernelcache.img4 -M IM4M -T rkrn -P "$dir"/ramdisk/kc.bpatch
            "$bin"/img4 -i "$dir"/ramdisk/kernelcache.dec -o "$dir"/ramdisk/kernelcache -M IM4M -T krnl -P "$dir"/ramdisk/kc.bpatch
            if [[ "$3" == "12."* ]]; then
                "$bin"/img4 -i "$dir"/ramdisk/trustcache.im4p -o "$dir"/ramdisk/trustcache.img4 -M IM4M -T rtsc
            fi
            "$bin"/img4 -i "$dir"/ramdisk/devicetree.dec -o "$dir"/ramdisk/devicetree.img4 -M IM4M -T rdtr
        fi
    fi
    cd ..
    rm -rf work
}
_download_boot_files() {
    ipswurl=$(curl -k -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$bin"/jq '.firmwares | .[] | select(.version=="'$3'")' | "$bin"/jq -s '.[0] | .url' --raw-output)
    rm -rf BuildManifest.plist
    mkdir -p "$dir"/$1/$3
    rm -rf work
    mkdir work
    cd work
    "$bin"/img4tool -e -s "$dir"/other/shsh/"${check}".shsh -m IM4M
    if [ ! -e "$dir"/$1/$3/kernelcache ]; then
        "$bin"/pzb -g BuildManifest.plist "$ipswurl"
        if [ ! -e "$dir"/$1/$3/kernelcache.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1) "$ipswurl"
            fn="$(awk "/""$2""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/$1/$3/kcache.raw -k $ivkey
            "$bin"/img4 -i $fn -o "$dir"/$1/$3/kernelcache.dec -k $ivkey -D
            pyimg4 im4p extract -i $fn -o "$dir"/$1/$3/kernelcache_pyimg4.dec --iv ${ivkey:0:32} --key ${ivkey:32} --extra "$dir"/$1/$3/kpp.bin
        fi
        if [ ! -e "$dir"/$1/$3/iBSS.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1) "$ipswurl"
            fn="$(awk "/""$2""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/$1/$3/iBSS.dec -k $ivkey
        fi
        if [ ! -e "$dir"/$1/$3/iBEC.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1) "$ipswurl"
            fn="$(awk "/""$2""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/$1/$3/iBEC.dec -k $ivkey
        fi
        if [ ! -e "$dir"/$1/$3/DeviceTree.dec ]; then
            "$bin"/pzb -g $(awk "/""$2""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1) "$ipswurl"
            fn="$(awk "/""$2""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]all_flash.*production[/]//')"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/$1/$3/DeviceTree.dec -k $ivkey
        fi
        if [ ! -e "$dir"/$1/$3/RestoreRamDisk.dmg ]; then
            "$bin"/pzb -g "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" "$ipswurl"
            fn="$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)"
            ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
            "$bin"/img4 -i $fn -o "$dir"/$1/$3/RestoreRamDisk.dmg -k $ivkey
        fi
        rm -rf BuildManifest.plist
        if [[ "$3" == "9."* ]]; then
            "$bin"/iBoot64Patcher "$dir"/$1/$3/iBSS.dec "$dir"/$1/$3/iBSS.patched
            "$bin"/iBoot64Patcher "$dir"/$1/$3/iBEC.dec "$dir"/$1/$3/iBEC.patched -b "-v rd=disk0s1s1 amfi=0xff cs_enforcement_disable=1 keepsyms=1 debug=0x2014e PE_i_can_has_debugger=1 amfi_get_out_of_my_way=1 amfi_allow_any_signature=1"
        elif [[ "$3" == "8."* ]]; then
            "$bin"/ipatcher "$dir"/$1/$3/iBSS.dec "$dir"/$1/$3/iBSS.patched
            "$bin"/ipatcher "$dir"/$1/$3/iBEC.dec "$dir"/$1/$3/iBEC.patched -b "-v rd=disk0s1s1 amfi=0xff cs_enforcement_disable=1 keepsyms=1 debug=0x2014e PE_i_can_has_debugger=1"
        else
            "$bin"/ipatcher "$dir"/$1/$3/iBSS.dec "$dir"/$1/$3/iBSS.patched
            "$bin"/ipatcher "$dir"/$1/$3/iBEC.dec "$dir"/$1/$3/iBEC.patched -b "-v rd=disk0s1s1 amfi=0xff cs_enforcement_disable=1 keepsyms=1 debug=0x2014e wdt=-1 PE_i_can_has_debugger=1 amfi_get_out_of_my_way=0x1 amfi_unrestrict_task_for_pid=0x0"
        fi
        if [[ "$3" == "8."* ]]; then
            "$bin"/img4 -i "$dir"/$1/$3/iBSS.patched -o "$dir"/$1/$3/iBSS.img4 -M IM4M -A -T ibss
            "$bin"/img4 -i "$dir"/$1/$3/iBEC.patched -o "$dir"/$1/$3/iBEC.img4 -M IM4M -A -T ibec
            if [[ "$1" == "iPhone6,2" || "$1" == "iPhone6,1" ]]; then
                "$bin"/seprmvr64lite "$dir"/jb/12A4331d_kcache.raw "$dir"/$1/$3/kcache.patched
                "$bin"/Kernel64Patcher "$dir"/$1/$3/kcache.patched "$dir"/$1/$3/kcache2.patched -t -p -f -a -m -g -s
                "$bin"/kerneldiff "$dir"/jb/12A4331d_kcache.raw "$dir"/$1/$3/kcache2.patched "$dir"/$1/$3/kc.bpatch
                "$bin"/img4 -i "$dir"/jb/12A4331d_kernelcache.dec -o "$dir"/$1/$3/kernelcache.img4 -M IM4M -T rkrn -P "$dir"/$1/$3/kc.bpatch
                "$bin"/img4 -i "$dir"/jb/12A4331d_kernelcache.dec -o "$dir"/$1/$3/kernelcache -M IM4M -T krnl -P "$dir"/$1/$3/kc.bpatch
            else
                "$bin"/seprmvr64lite "$dir"/$1/$3/kcache.raw "$dir"/$1/$3/kcache.patched
                "$bin"/Kernel64Patcher "$dir"/$1/$3/kcache.patched "$dir"/$1/$3/kcache2.patched -t -p -f -a -m -g -s
                "$bin"/kerneldiff "$dir"/$1/$3/kcache.raw "$dir"/$1/$3/kcache2.patched "$dir"/$1/$3/kc.bpatch
                "$bin"/img4 -i "$dir"/$1/$3/kernelcache.dec -o "$dir"/$1/$3/kernelcache.img4 -M IM4M -T rkrn -P "$dir"/$1/$3/kc.bpatch
                "$bin"/img4 -i "$dir"/$1/$3/kernelcache.dec -o "$dir"/$1/$3/kernelcache -M IM4M -T krnl -P "$dir"/$1/$3/kc.bpatch
            fi
            "$bin"/dtree_patcher "$dir"/$1/$3/DeviceTree.dec "$dir"/$1/$3/DeviceTree.patched -n
        elif [[ "$3" == "9."* ]]; then
            "$bin"/img4 -i "$dir"/$1/$3/iBSS.patched -o "$dir"/$1/$3/iBSS.img4 -M IM4M -A -T ibss
            "$bin"/img4 -i "$dir"/$1/$3/iBEC.patched -o "$dir"/$1/$3/iBEC.img4 -M IM4M -A -T ibec
            "$bin"/seprmvr64lite "$dir"/$1/$3/kcache.raw "$dir"/$1/$3/kcache.patched
            "$bin"/Kernel64Patcher "$dir"/$1/$3/kcache.patched "$dir"/$1/$3/kcache2.patched -e -l -f -t -m -a -s -p -v -g
            pyimg4 im4p create -i "$dir"/$1/$3/kcache2.patched -o "$dir"/$1/$3/kernelcache.im4p.img4 --extra "$dir"/$1/$3/kpp.bin -f rkrn --lzss
            pyimg4 im4p create -i "$dir"/$1/$3/kcache2.patched -o "$dir"/$1/$3/kernelcache.im4p --extra "$dir"/$1/$3/kpp.bin -f krnl --lzss
            pyimg4 img4 create -p "$dir"/$1/$3/kernelcache.im4p.img4 -o "$dir"/$1/$3/kernelcache.img4 -m IM4M
            pyimg4 img4 create -p "$dir"/$1/$3/kernelcache.im4p -o "$dir"/$1/$3/kernelcache -m IM4M
            "$bin"/dtree_patcher "$dir"/$1/$3/DeviceTree.dec "$dir"/$1/$3/DeviceTree.patched -n
        elif [[ "$3" == "7."* ]]; then
            "$bin"/img4 -i "$dir"/$1/$3/iBSS.patched -o "$dir"/$1/$3/iBSS.img4 -M IM4M -A -T ibss
            "$bin"/img4 -i "$dir"/$1/$3/iBEC.patched -o "$dir"/$1/$3/iBEC.img4 -M IM4M -A -T ibec
            "$bin"/seprmvr64lite "$dir"/$1/$3/kcache.raw "$dir"/$1/$3/kcache.patched
            "$bin"/Kernel64Patcher "$dir"/$1/$3/kcache.patched "$dir"/$1/$3/kcache2.patched -m -e -f -k
            "$bin"/kerneldiff "$dir"/$1/$3/kcache.raw "$dir"/$1/$3/kcache2.patched "$dir"/$1/$3/kc.bpatch
            "$bin"/img4 -i "$dir"/$1/$3/kernelcache.dec -o "$dir"/$1/$3/kernelcache.img4 -M IM4M -T rkrn -P "$dir"/$1/$3/kc.bpatch
            "$bin"/img4 -i "$dir"/$1/$3/kernelcache.dec -o "$dir"/$1/$3/kernelcache -M IM4M -T krnl -P "$dir"/$1/$3/kc.bpatch
            cp "$dir"/$1/$3/DeviceTree.dec "$dir"/$1/$3/DeviceTree.patched
        fi
        "$bin"/img4 -i "$dir"/$1/$3/DeviceTree.patched -o "$dir"/$1/$3/devicetree.img4 -A -M IM4M -T rdtr
    fi
    cd ..
    rm -rf work
}
_download_root_fs() {
    ipswurl=$(curl -k -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$bin"/jq '.firmwares | .[] | select(.version=="'$3'")' | "$bin"/jq -s '.[0] | .url' --raw-output)
    rm -rf BuildManifest.plist
    mkdir -p "$dir"/$1/$3
    rm -rf work
    mkdir work
    cd work
    "$bin"/img4tool -e -s "$dir"/other/shsh/"${check}".shsh -m IM4M
    if [ ! -e "$dir"/$1/$3/OS.tar ]; then
        if [ ! -e "$dir"/$1/$3/OS.dmg ]; then
            if [[ "$deviceid" == "iPhone7,2" || "$deviceid" == "iPhone7,1" || ! "$3" == "8.0" ]]; then
                "$bin"/pzb -g BuildManifest.plist "$ipswurl"
                "$bin"/pzb -g "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."OS"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" "$ipswurl"
                fn="$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."OS"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)"
                ivkey="$(java -jar ../Darwin/FirmwareKeysDl-1.0-SNAPSHOT.jar -ivkey $fn $3 $1)"
                "$bin"/dmg extract $fn "$dir"/$1/$3/OS.dmg -k $ivkey
            else
                # https://archive.org/download/Apple_iPhone_Firmware/Apple%20iPhone%206.1%20Firmware%208.0%20%288.0.12A4331d%29%20%28beta4%29/
                cd "$dir"/$1/$3
                "$bin"/aria2c https://ia903400.us.archive.org/4/items/Apple_iPhone_Firmware/Apple%20iPhone%206.1%20Firmware%208.0%20%288.0.12A4331d%29%20%28beta4%29/media_ipsw.rar
                "$bin"/7z x media_ipsw.rar
                "$bin"/7z x $(find . -name '*.ipsw*')
                "$bin"/dmg extract 058-01244-053.dmg OS.dmg -k 5c8b481822b91861c1d19590e790b306daaab2230f89dd275c18356d28fdcd47436a0737
                cd ../../work/
            fi
        fi
        "$bin"/dmg build "$dir"/$1/$3/OS.dmg "$dir"/$1/$3/rw.dmg
        hdiutil attach -mountpoint /tmp/ios "$dir"/$1/$3/rw.dmg
        sudo diskutil enableOwnership /tmp/ios
        sudo "$bin"/gnutar -cvf "$dir"/$1/$3/OS.tar -C /tmp/ios .
        hdiutil detach /tmp/ios
        rm -rf /tmp/ios
        "$bin"/irecovery -f /dev/null
    fi
    cd ..
    rm -rf work
}
_kill_if_running() {
    if (pgrep -u root -xf "$1" &> /dev/null > /dev/null); then
        sudo killall $1
    else
        if (pgrep -x "$1" &> /dev/null > /dev/null); then
            killall $1
        fi
    fi
}
# Check for required commands
if [ "$os" = 'Linux' ]; then
    linux_cmds='lsusb'
fi
for cmd in curl unzip python3 git ssh scp killall sudo grep pgrep java ${linux_cmds}; do
    if ! command -v "${cmd}" > /dev/null; then
        if [ "$cmd" = "python3" ]; then
            echo "[-] Command '${cmd}' not installed, please install it!";
            if [ "$os" = 'Darwin' ]; then
                if [ ! -e python-3.7.6-macosx10.6.pkg ]; then
                    curl -k https://www.python.org/ftp/python/3.7.6/python-3.7.6-macosx10.6.pkg -o python-3.7.6-macosx10.6.pkg
                fi
                open -W python-3.7.6-macosx10.6.pkg
            fi
            if ! command -v "${cmd}" > /dev/null; then
                cmd_not_found=1
            fi
        else
            if ! command -v "${cmd}" > /dev/null; then
                echo "[-] Command '${cmd}' not installed, please install it!";
                cmd_not_found=1
            fi
        fi
    fi
done
if [ "$cmd_not_found" = "1" ]; then
    exit 1
fi
if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); then
    "$bin"/dfuhelper.sh
fi
_wait_for_dfu
check=$("$bin"/irecovery -q | grep CPID | sed 's/CPID: //')
replace=$("$bin"/irecovery -q | grep MODEL | sed 's/MODEL: //')
deviceid=$("$bin"/irecovery -q | grep PRODUCT | sed 's/PRODUCT: //')
echo $deviceid
parse_cmdline "$@"
# Check for pyimg4
if ! python3 -c 'import pkgutil; exit(not pkgutil.find_loader("pyimg4"))'; then
    python3 -m pip install pyimg4
fi
_wait_for_dfu
if [[ "$boot" == 1 ]]; then
    _download_boot_files $deviceid $replace $1
    if [ -e "$dir"/$deviceid/$1/iBSS.img4 ]; then
        cd "$dir"/$deviceid/$1
        if [[ "$deviceid" == "iPhone7,2" || "$deviceid" == "iPhone7,1" ]]; then
            "$bin"/gaster pwn
        else
            "$bin"/ipwnder -p
        fi
        "$bin"/irecovery -f iBSS.img4
        "$bin"/irecovery -f iBSS.img4
        "$bin"/irecovery -f iBEC.img4
        "$bin"/irecovery -f devicetree.img4
        "$bin"/irecovery -c devicetree
        if [ -e ./trustcache.img4 ]; then
            "$bin"/irecovery -f trustcache.img4
            "$bin"/irecovery -c firmware
        fi
        "$bin"/irecovery -f kernelcache.img4
        "$bin"/irecovery -c bootx &
        cd ../../
        exit
    fi
    exit 0
fi
if [[ "$ramdisk" == 1 || "$restore" == 1 || "$dump_blobs" == 1 ]]; then
    if [[ ! -e "$dir"/$deviceid/0.0/apticket.der || ! -e "$dir"/$deviceid/0.0/sep-firmware.img4 || ! -e "$dir"/$deviceid/0.0/Baseband || ! -e "$dir"/$deviceid/0.0/keybags ]]; then
        read -p "what ios version are you running right now? " r
        _download_ramdisk_boot_files $deviceid $replace $r
    elif [[ "$1" == "7."* || "$1" == "8."* ]]; then
        _download_ramdisk_boot_files $deviceid $replace 8.4.1
    else
        _download_ramdisk_boot_files $deviceid $replace 11.4.1
    fi
    _download_boot_files $deviceid $replace $1
    _download_root_fs $deviceid $replace $1
    cd "$dir"/ramdisk
    if [[ "$deviceid" == "iPhone7,2" || "$deviceid" == "iPhone7,1" ]]; then
        "$bin"/gaster pwn
    else
        "$bin"/ipwnder -p
    fi
    "$bin"/irecovery -f iBSS.img4
    "$bin"/irecovery -f iBSS.img4
    "$bin"/irecovery -f iBEC.img4
    "$bin"/irecovery -f ramdisk.img4
    "$bin"/irecovery -c ramdisk
    "$bin"/irecovery -f devicetree.img4
    "$bin"/irecovery -c devicetree
    if [ -e ./trustcache.img4 ]; then
        "$bin"/irecovery -f trustcache.img4
        "$bin"/irecovery -c firmware
    fi
    "$bin"/irecovery -f kernelcache.img4
    "$bin"/irecovery -c bootx &
    cd ..
    sleep 8
    "$bin"/iproxy 2222 22 &
    sleep 2
    if [[ "$restore" == 1 ]]; then
        mkdir -p "$dir"/$deviceid/0.0/
        if [[ ! -e "$dir"/$deviceid/0.0/apticket.der || ! -e "$dir"/$deviceid/0.0/sep-firmware.img4 || ! -e "$dir"/$deviceid/0.0/Baseband || ! -e "$dir"/$deviceid/0.0/keybags ]]; then
            if [[ "$r" == "7."* || "$r" == "8."* || "$r" == "9."* || "$r" == "10.0"* || "$r" == "10.1"* || "$r" == "10.2"* ]]; then
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_hfs /dev/disk0s1s1 /mnt1" 2> /dev/null
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount -t hfs /dev/disk0s1s2 /mnt2" 2> /dev/null
            else
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "bash -c mount_filesystems" 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/apticket.der ]; then
                "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/Caches/apticket.der "$dir"/$deviceid/0.0/apticket.der 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/sep-firmware.img4 ]; then
                "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/usr/standalone/firmware/sep-firmware.img4 "$dir"/$deviceid/0.0/sep-firmware.img4 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/FUD ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt1/usr/standalone/firmware/FUD "$dir"/$deviceid/0.0/FUD 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/Baseband ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt1/usr/local/standalone/firmware/Baseband "$dir"/$deviceid/0.0/Baseband 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/firmware ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt1/usr/standalone/firmware "$dir"/$deviceid/0.0/firmware 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/local ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt1/usr/local "$dir"/$deviceid/0.0/local 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/keybags ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt2/keybags "$dir"/$deviceid/0.0/keybags 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/wireless ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt2/wireless "$dir"/$deviceid/0.0/wireless 2> /dev/null
            fi
            if [ ! -e "$dir"/$deviceid/0.0/com.apple.factorydata ]; then
                "$bin"/sshpass -p "alpine" scp -r -P 2222 root@localhost:/mnt1/System/Library/Caches/com.apple.factorydata "$dir"/$deviceid/0.0/com.apple.factorydata 2> /dev/null
            fi
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/umount /mnt1" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/umount /mnt2" 2> /dev/null
            if [[ "$1" == "7."* || "$1" == "8."* ]]; then
                rm -rf ramdisk
                _download_ramdisk_boot_files $deviceid $replace 8.4.1
            else
                rm -rf ramdisk
                _download_ramdisk_boot_files $deviceid $replace 11.4.1
            fi
        fi
        if [ ! -e "$dir"/$deviceid/0.0/apticket.der ]; then
            echo "missing ./apticket.der, which is required in order to proceed. exiting.."
            exit
        fi
        if [ ! -e "$dir"/$deviceid/0.0/sep-firmware.img4 ]; then
            echo "missing ./sep-firmware.img4, which is required in order to proceed. exiting.."
            exit
        fi
        if [ ! -e "$dir"/$deviceid/0.0/Baseband ]; then
            echo "missing ./Baseband, which is required in order to proceed. exiting.."
            exit
        fi
        if [ ! -e "$dir"/$deviceid/0.0/keybags ]; then
            echo "missing ./keybags, which is required in order to proceed. exiting.."
            exit
        fi
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "lwvm init" 2> /dev/null
        sleep 1
        $("$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/reboot &" 2> /dev/null &)
        _kill_if_running iproxy
        echo "device should now reboot into recovery, pls wait"
        echo "once in recovery you should follow instructions online to go back into dfu"
        if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); then
            "$bin"/dfuhelper.sh
        fi
        _wait_for_dfu
        cd "$dir"/ramdisk
        if [[ "$deviceid" == "iPhone7,2" || "$deviceid" == "iPhone7,1" ]]; then
            "$bin"/gaster pwn
        else
            "$bin"/ipwnder -p
        fi
        "$bin"/irecovery -f iBSS.img4
        "$bin"/irecovery -f iBSS.img4
        "$bin"/irecovery -f iBEC.img4
        "$bin"/irecovery -f ramdisk.img4
        "$bin"/irecovery -c ramdisk
        "$bin"/irecovery -f devicetree.img4
        "$bin"/irecovery -c devicetree
        if [ -e ./trustcache.img4 ]; then
            "$bin"/irecovery -f trustcache.img4
            "$bin"/irecovery -c firmware
        fi
        "$bin"/irecovery -f kernelcache.img4
        "$bin"/irecovery -c bootx &
        cd ..
        sleep 8
        "$bin"/iproxy 2222 22 &
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "cat /gpt.txt | gptfdisk /dev/rdisk0s1" 2> /dev/null
        sleep 2
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/sync" 2> /dev/null
        sleep 1
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/sync" 2> /dev/null
        sleep 1
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/sync" 2> /dev/null
        sleep 1
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/newfs_hfs -s -v System -J -b 4096 -n a=4096,c=4096,e=4096 /dev/disk0s1s1"
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/newfs_hfs -s -v Data -J -b 4096 -n a=4096,c=4096,e=4096 /dev/disk0s1s2"
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_hfs /dev/disk0s1s1 /mnt1" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount -w -t hfs -o suid,dev /dev/disk0s1s2 /mnt2" 2> /dev/null
        "$bin"/sshpass -p 'alpine' scp -P 2222 "$dir"/$deviceid/$1/OS.tar root@localhost:/mnt2 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "tar -xvf /mnt2/OS.tar -C /mnt1"
        if [[ "$1" == "7."* ]]; then
            "$bin"/sshpass -p 'alpine' scp -P 2222 "$dir"/jb/cydia_ios7.tar root@localhost:/mnt2 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "tar -xvf /mnt2/cydia_ios7.tar -C /mnt1"
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/cydia_ios7.tar" 2> /dev/null
        elif [[ "$1" == "8."* || "$1" == "9."* ]]; then
            "$bin"/sshpass -p 'alpine' scp -P 2222 "$dir"/jb/cydia.tar root@localhost:/mnt2 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "tar -xvf /mnt2/cydia.tar -C /mnt1"
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/cydia.tar" 2> /dev/null
        fi
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mv -v /mnt1/private/var/* /mnt2" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mkdir -p /mnt1/usr/local/standalone/firmware/Baseband" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mkdir /mnt2/keybags" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mkdir -p /mnt2/wireless/baseband_data" 2> /dev/null
        "$bin"/sshpass -p "alpine" scp -r -P 2222 "$dir"/$deviceid/0.0/keybags root@localhost:/mnt2 2> /dev/null
        "$bin"/sshpass -p "alpine" scp -r -P 2222 "$dir"/$deviceid/0.0/Baseband root@localhost:/mnt1/usr/local/standalone/firmware 2> /dev/null
        "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/0.0/apticket.der root@localhost:/mnt1/System/Library/Caches/ 2> /dev/null
        "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/0.0/sep-firmware.img4 root@localhost:/mnt1/usr/standalone/firmware/ 2> /dev/null
        if [ -e "$dir"/$deviceid/0.0/FUD ]; then
            "$bin"/sshpass -p "alpine" scp -r -P 2222 "$dir"/$deviceid/0.0/FUD root@localhost:/mnt1/usr/standalone/firmware 2> /dev/null
        fi
        if [ -e "$dir"/$deviceid/0.0/com.apple.factorydata ]; then
            "$bin"/sshpass -p "alpine" scp -r -P 2222 "$dir"/$deviceid/0.0/com.apple.factorydata root@localhost:/mnt1/System/Library/Caches 2> /dev/null
        fi
        if [ -e "$dir"/$deviceid/0.0/wireless ]; then
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mkdir -p /mnt2/wireless/Library/Preferences/" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mkdir -p /mnt2/wireless/Library/Databases/" 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -r -P 2222 "$dir"/$deviceid/0.0/wireless/Library/Preferences/ root@localhost:/mnt2/wireless/Library 2> /dev/null
        fi
        if [[ "$1" == "7."* || "$1" == "8."* || "$1" == "9."* ]]; then
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/fstab_rw root@localhost:/mnt1/etc/fstab 2> /dev/null
        else
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/fstab root@localhost:/mnt1/etc/ 2> /dev/null
        fi
        #"$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt1/Applications/Setup.app"
        "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/data_ark.plist_ios7.tar root@localhost:/mnt2/ 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "tar -xvf /mnt2/data_ark.plist_ios7.tar -C /mnt2" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/data_ark.plist_ios7.tar" 2> /dev/null
        if [[ "$1" == "8."* || "$1" == "9."* ]]; then
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/data_ark.plist_ios8.tar root@localhost:/mnt2/ 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "tar -xvf /mnt2/data_ark.plist_ios8.tar -C /mnt2" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/data_ark.plist_ios8.tar" 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/PrivateFrameworks/MobileActivation.framework/Support/mobactivationd "$dir"/$deviceid/$1/mobactivationd.raw 2> /dev/null
            "$bin"/mobactivationd64patcher "$dir"/$deviceid/$1/mobactivationd.raw "$dir"/$deviceid/$1/mobactivationd.patched -b -c -d 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/mobactivationd.patched root@localhost:/mnt1/System/Library/PrivateFrameworks/MobileActivation.framework/Support/mobactivationd 2> /dev/null
        fi
        "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/com.saurik.Cydia.Startup.plist root@localhost:/mnt1/System/Library/LaunchDaemons 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown root:wheel /mnt1/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/OS.tar" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/log/asl/SweepStore" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/mobile/Library/PreinstalledAssets/*" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/mobile/Library/Preferences/.GlobalPreferences.plist" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt2/mobile/.forward" 2> /dev/null
        if [[ "$1" == "7."*  ]]; then
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/untether_ios7.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar --preserve-permissions -xvf /mnt1/untether_ios7.tar -C /mnt1/' 2> /dev/null
            # adds wtfis.app to /Applications which runs evasi0n7 jailbreak on ios 7 to enable tweaks to work
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/wtfis.app_ios7.tar root@localhost:/mnt1/
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar --preserve-permissions -xvf /mnt1/wtfis.app_ios7.tar -C /mnt1/Applications' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "touch /mnt1/.installed_wtfis" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "chmod 777 /mnt1/.installed_wtfis" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "touch /mnt1/evasi0n7-installed" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "chmod 777 /mnt1/evasi0n7-installed" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "mkdir -p /mnt2/mobile/Media/" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "touch /mnt2/mobile/Media/.evasi0n7_installed" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "chmod 777 /mnt2/mobile/Media/.evasi0n7_installed" 2> /dev/null
        elif [[ "$1" == "9."*  ]]; then
            # adds /bin/launchctl and /wtfis/loadruncmd which are both required for wtfis.app to work properly
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/untether_ios9.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar --preserve-permissions -xvf /mnt1/untether_ios9.tar -C /mnt1/' 2> /dev/null
            # adds wtfis.app to /Applications which simply only runs uicache and resprings on ios 9
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/wtfis.app_ios9.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar --preserve-permissions -xvf /mnt1/wtfis.app_ios9.tar -C /mnt1/Applications' 2> /dev/null
            # make wtfis not try to bootstrap cydia
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "touch /mnt1/.installed_wtfis" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "chown root:wheel /mnt1/.installed_wtfis" 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "chmod 777 /mnt1/.installed_wtfis" 2> /dev/null
            # fix cydia launch daemon
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'cp /mnt1/usr/libexec/CrashHousekeeping /mnt1/usr/libexec/CrashHousekeeping_o' 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/startup_ios9.sh root@localhost:/mnt1/usr/libexec/CrashHousekeeping 2> /dev/null
        fi
        if [[ "$1" == "9."* || "$1" == "8."* ]]; then
            read -p "would you like to also install Evermusic_Free.app? " r
            if [[ "$r" = 'yes' || "$r" = 'y' ]]; then
                "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/Evermusic_Free.app.tar root@localhost:/mnt1/
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "tar -xvf /mnt1/Evermusic_Free.app.tar -C /mnt1/Applications/"
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/Applications/Evermusic_Free.app'
            fi
        fi
        "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/kernelcache root@localhost:/mnt1/System/Library/Caches/com.apple.kernelcaches 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "touch /mnt1/.cydia_no_stash" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown root:wheel /mnt1/.cydia_no_stash" 2> /dev/null
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "chmod 777 /mnt1/.cydia_no_stash" 2> /dev/null
        if [[ "$1" == "8."* ]]; then
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/AppleInternal.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/PrototypeTools.framework_ios8.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/CoreServices/SystemVersion.plist "$dir"/$deviceid/$1/SystemVersion.plist 2> /dev/null
            sed -i -e 's/<\/dict>/<key>ReleaseType<\/key><string>Internal<\/string><key>ProductType<\/key><string>Internal<\/string><\/dict>/g' "$dir"/$deviceid/$1/SystemVersion.plist 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/SystemVersion.plist root@localhost:/mnt1/System/Library/CoreServices/SystemVersion.plist 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/SpringBoard-Internal.strings root@localhost:/mnt1/System/Library/CoreServices/SpringBoard.app/en.lproj/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/SpringBoard-Internal.strings root@localhost:/mnt1/System/Library/CoreServices/SpringBoard.app/en_GB.lproj/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/com.apple.springboard_ios8.plist root@localhost:/mnt2/mobile/Library/Preferences/com.apple.springboard.plist 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar -xvf /mnt1/PrototypeTools.framework_ios8.tar -C /mnt1/System/Library/PrivateFrameworks/'
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/System/Library/PrivateFrameworks/PrototypeTools.framework' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/PrototypeTools.framework_ios8.tar' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar -xvf /mnt1/AppleInternal.tar -C /mnt1/'
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/AppleInternal/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/AppleInternal.tar' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt2/mobile/Library/Caches/com.apple.MobileGestalt.plist' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/HealthMigrator.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MobileNotes.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MobileSlideShow.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MobileSafari.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MapsDataClassMigrator.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/InternationalSupportMigrator.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MobileAsset.migrator/' 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/PrivateFrameworks/DataMigration.framework/XPCServices/com.apple.datamigrator.xpc/com.apple.datamigrator "$dir"/$deviceid/$1/com.apple.datamigrator 2> /dev/null
            "$bin"/datamigrator64patcher "$dir"/$deviceid/$1/com.apple.datamigrator "$dir"/$deviceid/$1/com.apple.datamigrator_patched -n
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/com.apple.datamigrator_patched root@localhost:/mnt1/System/Library/PrivateFrameworks/DataMigration.framework/XPCServices/com.apple.datamigrator.xpc/com.apple.datamigrator 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/usr/libexec/lockdownd "$dir"/$deviceid/$1/lockdownd.raw 2> /dev/null
            "$bin"/lockdownd64patcher "$dir"/$deviceid/$1/lockdownd.raw "$dir"/$deviceid/$1/lockdownd.patched -u -l 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/lockdownd.patched root@localhost:/mnt1/usr/libexec/lockdownd 2> /dev/null
        elif [[ "$1" == "7."* ]]; then
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/AppleInternal.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/PrototypeTools.framework.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/CoreServices/SystemVersion.plist "$dir"/$deviceid/$1/SystemVersion.plist 2> /dev/null
            sed -i -e 's/<\/dict>/<key>ReleaseType<\/key><string>Internal<\/string><key>ProductType<\/key><string>Internal<\/string><\/dict>/g' "$dir"/$deviceid/$1/SystemVersion.plist 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/SystemVersion.plist root@localhost:/mnt1/System/Library/CoreServices/SystemVersion.plist 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/SpringBoard-Internal.strings root@localhost:/mnt1/System/Library/CoreServices/SpringBoard.app/en.lproj/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/SpringBoard-Internal.strings root@localhost:/mnt1/System/Library/CoreServices/SpringBoard.app/en_GB.lproj/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/com.apple.springboard.plist root@localhost:/mnt2/mobile/Library/Preferences/com.apple.springboard.plist 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar -xvf /mnt1/PrototypeTools.framework.tar -C /mnt1/System/Library/PrivateFrameworks/'
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/System/Library/PrivateFrameworks/PrototypeTools.framework' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/PrototypeTools.framework.tar' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar -xvf /mnt1/AppleInternal.tar -C /mnt1/'
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/AppleInternal/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/AppleInternal.tar' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt2/mobile/Library/Caches/com.apple.MobileGestalt.plist' 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/usr/libexec/lockdownd "$dir"/$deviceid/$1/lockdownd.raw 2> /dev/null
            "$bin"/lockdownd64patcher "$dir"/$deviceid/$1/lockdownd.raw "$dir"/$deviceid/$1/lockdownd.patched -u -l -b 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/lockdownd.patched root@localhost:/mnt1/usr/libexec/lockdownd 2> /dev/null
        elif [[ "$1" == "9."* ]]; then
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/AppleInternal.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/PrototypeTools.framework_ios9.tar root@localhost:/mnt1/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/CoreServices/SystemVersion.plist "$dir"/$deviceid/$1/SystemVersion.plist 2> /dev/null
            sed -i -e 's/<\/dict>/<key>ReleaseType<\/key><string>Internal<\/string><key>ProductType<\/key><string>Internal<\/string><\/dict>/g' "$dir"/$deviceid/$1/SystemVersion.plist 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/$deviceid/$1/SystemVersion.plist root@localhost:/mnt1/System/Library/CoreServices/SystemVersion.plist 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/SpringBoard-Internal.strings root@localhost:/mnt1/System/Library/CoreServices/SpringBoard.app/en.lproj/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/SpringBoard-Internal.strings root@localhost:/mnt1/System/Library/CoreServices/SpringBoard.app/en_GB.lproj/ 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 "$dir"/jb/com.apple.springboard_ios9.plist root@localhost:/mnt2/mobile/Library/Preferences/com.apple.springboard.plist 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar -xvf /mnt1/PrototypeTools.framework_ios9.tar -C /mnt1/System/Library/PrivateFrameworks/'
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/System/Library/PrivateFrameworks/PrototypeTools.framework' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/PrototypeTools.framework_ios9.tar' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'tar -xvf /mnt1/AppleInternal.tar -C /mnt1/'
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost '/usr/sbin/chown -R root:wheel /mnt1/AppleInternal/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/AppleInternal.tar' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt2/mobile/Library/Caches/com.apple.MobileGestalt.plist' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MobileSafari.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/Calendar.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MapsDataClassMigrator.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/MobileSlideShow.migrator/' 2> /dev/null
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost 'rm -rf /mnt1/System/Library/DataClassMigrators/iapmigrator.migrator/' 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/usr/libexec/lockdownd "$dir"/$deviceid/$1/lockdownd.raw 2> /dev/null
            "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/PrivateFrameworks/MobileActivation.framework/Support/mobactivationd "$dir"/$deviceid/$1/mobactivationd.raw 2> /dev/null
        fi
        "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -rf /mnt1/usr/lib/libmis.dylib" 2> /dev/null
        if [[ "$1" == "9."* ]]; then
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram -c" 2> /dev/null
        fi
        $("$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/reboot &" 2> /dev/null &)
        if [ -e "$dir"/$deviceid/$1/iBSS.img4 ]; then
            if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); then
                "$bin"/dfuhelper.sh
            fi
            _wait_for_dfu
            cd "$dir"/$deviceid/$1
            if [[ "$deviceid" == "iPhone7,2" || "$deviceid" == "iPhone7,1" ]]; then
                "$bin"/gaster pwn
            else
                "$bin"/ipwnder -p
            fi
            "$bin"/irecovery -f iBSS.img4
            "$bin"/irecovery -f iBSS.img4
            "$bin"/irecovery -f iBEC.img4
            "$bin"/irecovery -f devicetree.img4
            "$bin"/irecovery -c devicetree
            if [ -e ./trustcache.img4 ]; then
                "$bin"/irecovery -f trustcache.img4
                "$bin"/irecovery -c firmware
            fi
            "$bin"/irecovery -f kernelcache.img4
            "$bin"/irecovery -c bootx &
            cd ../../
        fi
        _kill_if_running iproxy
        if [[ "$1" == "8.0" ]]; then
            echo "done"
            exit
        fi
        echo "done"
        exit
    else
        if [[ "$r" == "7."* || "$r" == "8."* || "$r" == "9."* || "$r" == "10.0"* || "$r" == "10.1"* || "$r" == "10.2"* ]]; then
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount -w -t hfs /dev/disk0s1s1 /mnt1" 2> /dev/null
            if [[ "$1" == "7."* ]]; then
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount -t hfs /dev/disk0s1s2 /mnt2" 2> /dev/null
            else
                "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount -w -t hfs /dev/disk0s1s2 /mnt2" 2> /dev/null
            fi
        else
            "$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "bash -c mount_filesystems" 2> /dev/null
        fi
        if [[ "$dump_blobs" == 1 ]]; then
            mkdir -p "$dir"/$deviceid/0.0/
            if [[ ! -e "$dir"/$deviceid/0.0/apticket.der ]]; then
                "$bin"/sshpass -p "alpine" scp -P 2222 root@localhost:/mnt1/System/Library/Caches/apticket.der "$dir"/$deviceid/0.0/apticket.der 2> /dev/null
            fi
            if [[ -e "$dir"/$deviceid/0.0/apticket.der ]]; then
                echo "$dir"/$deviceid/0.0/apticket.der
            fi
        fi
        ssh -p2222 root@localhost
        $("$bin"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/reboot &" 2> /dev/null &)
    fi
fi
} | tee logs/"$(date +%T)"-"$(date +%F)"-"$(uname)"-"$(uname -r)".log