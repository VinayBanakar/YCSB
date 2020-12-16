#!/bin/bash
# ./ycsb-rocks.sh 2000000 2000000 6 mq-deadline uniform
## distributions: uniform, zipfian, hotspot, sequential, exponential or latest
rCount=$1
opCount=$2
thread=$3
sched=$4
dist=$5
logFile=rocks-$opCount-$thread-$dist.log
dataPath=/fastdisk/run-log/$sched
filePath=$dataPath/$logFile
bpfLog=$dataPath/bpf-$opCount-$thread-$dist.log

#Delete all existing data
rm -rf /fastdisk/ycsb-rocksdb-data/*

# create the dir required
mkdir -p $dataPath

start_ioSched(){
    secs=20
    endTime=$(( $(date +%s) + secs ))
    while [ $(date +%s) -lt $endTime ]; do
        if (( $(ps -ef | grep -v grep | grep -v taskset | grep 'java -cp' | wc -l) >= 1 )); then
            # kill any existing traces first
            sudo pkill bpftrace

            #sudo /usr/sbin/ioSched.bt $(pgrep -f 'java -cp') >> $dataPath/$1 &

sudo bpftrace -e "
BEGIN
{
   @t_start = nsecs;
}
kprobe:blk_account_io_start
/ pid == $(pgrep -f 'java -cp') / 
{
    @start[arg0] = nsecs;
}
kprobe:blk_mq_start_request
/ @start[arg0] != 0  && pid == $(pgrep -f 'java -cp') /
{
    @tmp1 = (nsecs - @start[arg0])/1000;
    @queue_time = hist(@tmp1);
    @queue_time_stat = stats(@tmp1);
    @rq_count += 1;
    delete(@tmp1);
}
kprobe:bio_attempt_back_merge
/ @start[arg0] != 0 && pid == $(pgrep -f 'java -cp') /
{
        @back_merge = count();

}
kprobe:bio_attempt_front_merge
/ @start[arg0] != 0 && pid == $(pgrep -f 'java -cp') /
{
        @front_merge = count();

}
kprobe:blk_account_io_done
/ @start[arg0] != 0 /
{
     @tmp2 = (nsecs - @start[arg0])/1000;
     @latency = hist(@tmp2);
     @latency_stat = stats(@tmp2);
     delete(@start[arg0]);
     delete(@tmp2);
}
END
{
        @t_end = (nsecs - @t_start)/1000000000;
        @throughput = @rq_count/@t_end;
        clear(@start);
        clear(@t_start);
        clear(@t_end);
}" >> $dataPath/$1-$opCount-$thread-$dist &

            sleep 1
            io_pid=$(sudo pgrep bpftrace)
            sudo taskset -cp 6 $io_pid
            echo ":::: STARTING ioSched $1 PID $io_pid::::" >> $bpfLog

            break
        fi
    done
}

# kill after ycsb load is finished. Arg is pid.
kill_ioSched(){
    while true; do
        sleep 2
        if (( $(ps -ef | grep -v grep | grep -v taskset | grep java | wc -l) < 1 )) && (( $(ps -ef | grep -v grep | grep -v taskset | grep bpftrace | wc -l) >= 1 )); then
            io_pid=$(sudo pgrep bpftrace)
            echo ":::: ENDING ioSched PID $io_pid ::::" >> $bpfLog
            #echo "=============== $(ps -ef | grep -v grep | grep -v taskset | grep java | wc -l) ==============="
            sudo kill $io_pid
            break
        fi
    done
}

gather_queue_size(){
    while true; do
        # rq_tick_start=$(awk '{print $9 }' /sys/block/sdb/stat)
        # sleep 1
        # echo $rq_tick_start >> $dataPath/queue-$1-$opCount-$thread-$dist.log & 


        rq_tick_start=$(awk '{if ($3 =="sda") { print $14 }}' /proc/diskstats)
        sleep 1
        rq_tick_end=$(awk '{if ($3 =="sda") { print $14 }}' /proc/diskstats)
        tmp=$((($rq_tick_end - $rq_tick_start)))
        q_size=$(bc <<< "scale=2; $tmp / 1000.0")
        echo $q_size >> $dataPath/queue-$1-$opCount-$thread-$dist.log & 
        if (( $(ps -ef | grep -v grep | grep -v taskset | grep java | wc -l) < 1 )) && (( $(ps -ef | grep -v grep | grep -v taskset | grep bpftrace | wc -l) < 1 )); then
            break;
        fi
    done
}


sudo sync
sudo sh -c "/bin/echo 3 > /proc/sys/vm/drop_caches"
## load A
echo "=== Load workload A ===" >> $filePath
taskset -c 10-19 ./bin/ycsb load rocksdb -s -P workloads/workloada -p rocksdb.dir=/fastdisk/ycsb-rocksdb-data -p recordcount=$rCount -p operationcount=$opCount -p requestdistribution=$dist -threads $thread -s >> $filePath &
start_ioSched 'load-a' &
gather_queue_size 'load-a' &

kill_ioSched $ioSched_pid
# killSched_pid=$!
# sudo taskset -cp 5 $killSched_pid

## Run A to F (no E)
for var in a b c d f; do
#for var in a ; do
    sleep 5
    if (( $(ps -ef | grep -v grep | grep -v taskset | grep java | wc -l) >= 1 )); then
        echo "[== ERROR ==] KILLING JAVA " >> $filePath
        sudo pkill java
    fi

    sudo sync
    sudo sh -c "/bin/echo 3 > /proc/sys/vm/drop_caches"
    echo "=== Run workload $var ===" >> $filePath
    taskset -c 10-19 ./bin/ycsb run rocksdb -s -P workloads/workload${var} -p rocksdb.dir=/fastdisk/ycsb-rocksdb-data -p recordcount=$rCount -p operationcount=$opCount -p requestdistribution=$dist -threads $thread -s >> $filePath &
    
    
    start_ioSched run-$var &
    gather_queue_size run-$var &
    
    kill_ioSched
    # killSched_pid=$!
    # echo "==== kill_ioSched PID $killSched_pid ====" >> $filePath
    # disown
    # sudo taskset -cp 5 $killSched_pid
done

# any remaining traces
sudo pkill bpftrace

#Delete all existing data
rm -rf /fastdisk/ycsb-rocksdb-data/*

# Clear caches
# Load E
# Run E
