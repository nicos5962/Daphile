#! /bin/bash
awk '{

    unit[1]="day"
    unit[2]="hour"
    unit[3]="minute"
    unit[4]="second"

    conv[1]=86400
    conv[2]=3600
    conv[3]=60
    conv[4]=1

    uptime = $1
    limit = int(uptime / 1000)

    cnt=0
    upstr=""
    for (ind = 1; ind <= 4; ind++) {

    tmp = int(uptime / conv[ind])

    if (tmp == 1) {
        str[ind]=sprintf("1 %s",unit[ind])
            cnt++
    } else if (tmp > 1) {
        str[ind]=sprintf("%d %ss", tmp, unit[ind])
            cnt++
    } else {
        str[ind]=""
    }

    if (upstr != "" && str[ind] != "")
        upstr = upstr ", " str[ind]
    else
        upstr = upstr str[ind]

    uptime %= conv[ind]

    if (cnt >= 2) {
        break
    } else if (cnt == 1) {
            cnt++
        }
    }
    printf("%s\n", upstr)

}' /proc/uptime
