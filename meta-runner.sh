#!/bin/bash
disk=sda
# uniform zipfian hotspot sequential exponential
#sudo sh -c "echo "mq-deadline" | sudo tee /sys/block/$disk/queue/scheduler"
#for var in zipfian; do
#	./ycsb-rocks.sh 1000000 1000000 4 mq-deadline $var
#done

#sudo sh -c "echo "bfq" | sudo tee /sys/block/$disk/queue/scheduler"
#for var in zipfian; do
#	./ycsb-rocks.sh 1000000 1000000 4 bfq $var
#done

#sudo sh -c "echo "none" | sudo tee /sys/block/$disk/queue/scheduler"
#for var in zipfian; do
#	./ycsb-rocks.sh 1000000 1000000 4 none $var
#done

sudo sh -c "echo "kyber" | sudo tee /sys/block/$disk/queue/scheduler"
for var in zipfian; do
	./ycsb-rocks.sh 1000000 1000000 4 kyber $var
done
