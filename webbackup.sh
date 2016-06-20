#!/bin/bash

currtime=$(date +%Y%m%d.%H%M%S)        # Current time YMD.HMS
curunixtime=$(date +%s)                # Current time in seconds
scriptdir=$(dirname $(readlink -e $0)) # Full path to running script, even if it runed from link
configdir="$scriptdir/configs"         # Dir with configs of vhosts
workdir="$scriptdir/workdir"           # Tmp dir for creating backups
maxbackupage=60                        # Days

# Include logginig module
# https://github.com/helldweller/bashlog
logging="$scriptdir/bashlog/logging.sh"
[ -f $logging ] || git clone https://github.com/helldweller/bashlog
#source $logging

source "$scriptdir/config.sh" # Main varables. Such as ftp user name, pass, etc..

let "mintime = curunixtime - maxbackupage * 86400"
printf "Backup\'s earlier $(date -d @$mintime) are removed!\n"

printf "Cleaning workdir...\n"
rm -rf $workdir/* # 2>/dev/null

ftpls=$(mktemp)
ftp2ls=$(mktemp)
ftpcmd=$(mktemp)
lftp -u $ftpuser,$ftppass $ftpip/$ftptd <<EOF
ls ./ > $ftpls
bye
EOF
cat $ftpls

# Find vhosts config; Include and make backup for each
find $configdir -type f -name *\.conf | while read -r file; do
    :>$ftp2ls
    printf "Including backup config $file\n";
    source $file
    backupto="$workdir/$backupname"
    mkdir -p $backupto
    backupsqlpath="$backupto/$currtime.sql.gz"
    backupfilepath="$backupto/$currtime.tar.gz"
    printf "Backuping MySQL database $dbname for vhost $backupname\n"
    # Backup MySQL database
    mysqldump -u $sqluser -p$sqlpass $dbname --allow-keywords --create-options --complete-insert --default-character-set=$charset --add-drop-table | gzip > $backupsqlpath
    printf "Backuping htdocs files for vhost $backupname\n"
    # Backup htdocs dir
    cd $backupfilesfrom && tar -cpPzf $backupfilepath .
    printf "Copyng $backupname backups to ftp server $ftpip\n"

# dirty code, but works
    ifdir=$(grep -E " $backupname$" $ftpls | awk '{print $3}')
    case "$ifdir" in
    "<DIR>" )
        # $backupname DIR exist. nothing to do
        :
    ;;
    [0-9]* )
        printf "$backupname already exists and is the FILE!\n" >&2
        exit 1
    ;;
    * )
        # dir not found. making dir"
        printf "mkdir -p /$ftptd/$backupname\n" >> $ftpcmd
    ;;
    esac

    #printf "mkdir -p -f /$ftptd/$backupname\n" >> $ftpcmd
    printf "cd /$ftptd/$backupname\n" >> $ftpcmd
    printf "put $backupfilepath\n" >> $ftpcmd
    printf "put $backupsqlpath\n" >> $ftpcmd
    printf "ls ./ > $ftp2ls\n" >> $ftpcmd
    printf "bye\n" >> $ftpcmd
    lftp -u $ftpuser,$ftppass $ftpip/$ftptd < $ftpcmd
    :>$ftpcmd

    # Rotation backups
    if [ -s $ftp2ls ]; then
        while read line; do
            #Convert backupname to unix time format
            filename=$(awk '{print $4}' <<< $line)
            backuptime=$(date -d "$(sed -r 's#.*([0-9]{4})([0-9]{2})([0-9]{2})\.([0-9]{2})([0-9]{2})([0-9]{2}).*#\1/\2/\3 \4:\5:\6#' <<< $filename)" "+%s" 2>/dev/null; retval=$?)
            if [[ $retval -eq 0 ]] && [[ $backuptime =~ ^[0-9]+$ ]]; then
                if [ $backuptime -lt $mintime ]; then
                    printf "Removing backup /$ftptd/$backupname/$filename\n"
                    printf "rm /$ftptd/$backupname/$filename\n" >> $ftpcmd
                fi
            else
                printf "Unknown file /$ftptd/$backupname/$filename\n" >&2
            fi
        done < $ftp2ls
        if [ -s $ftpcmd ]; then
#            sed -i -e "1 s/^/cd \/$ftptd\/$backupname\n/;" $ftpcmd
            printf "bye\n" >> $ftpcmd
            lftp -u $ftpuser,$ftppass $ftpip/$ftptd < $ftpcmd
            :>$ftpcmd
        fi # else no old backups
    else
        printf "Dir $backupname is empty. Nothing to do.\n" >&2
    fi
done

# end of script
rm $ftpls
rm $ftp2ls
rm $ftpcmd
exit 0