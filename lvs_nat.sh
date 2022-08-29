#!/bin/bash
########################################
# Author:hackwu
# time:2022年08月30日 星期二 00时10分45秒
# filename:test.sh
# Script description:
########################################

set -u

SET_RS=ON					#是否对RS进行配置，只用配置一次就行了

VIP=192.168.23.200		
port=80
policy=rr						#调度的策略
mod=n						#调度模式
interface=ens33:1				#网卡子接口
	
RS_gw=192.168.20.18	        #真实服务器的网关，使用NAT模式的时候，需要配置这个。

declare -A RIPS	
# 1 表示192.168.20.14这个主机的密码;
RIPS=(
[192.168.23.16]=1			  
[192.168.23.15]=1
[192.168.23.13]=1
)

########################
set +u
if [ -z "$1" ];then
	 echo "缺少选项"
	 echo "Usage: $0 {start|stop|status}"
	 exit
	
fi
set -u

function set_rs {

if [ "$mod" == "n"  ];then
function fun {
#	参数：$1:主机ip； 
/usr/bin/expect <<-EOF
spawn ssh root@$1 "route del default;route add default gw $RS_gw"
expect {
    yes/no { send "yes\r";exp_continue;}
    password { send "$2\r"; }
}
expect eof
EOF
}
fi

if [ "$mod" == "g"  ];then
function fun {
#	参数：$1:主机ip；$2:密码
/usr/bin/expect <<-EOF
spawn ssh root@$1 "echo 1 > /proc/sys/net/ipv4/conf/lo/arp_ignore;
echo 2 > /proc/sys/net/ipv4/conf/lo/arp_announce;
echo 1 > /proc/sys/net/ipv4/conf/all/arp_ignore;
echo 2 > /proc/sys/net/ipv4/conf/all/arp_announce;
ifconfig lo:0 $VIP  broadcast $VIP netmask 255.255.255.255 up;
route add -host $VIP dev lo:0
"
expect {
    yes/no { send "yes\r";exp_continue;}
    password { send "$2\r"; }
}
expect eof
EOF
}
fi


  rpm -qa|grep expect >> /dev/null
  if [ $? -ne 0 ];then
      yum -y install expect
  fi
  #清空lvs规则
	for ip in ${!RIPS[*]}
	do
	{
		if ! ping -c1 -W2 $ip &>/dev/null ;then
			echo "$ip ping不通，请检查ip是否书写错误！！"
			exit	
		fi
	 	passwd=${RIPS[$ip]}
		fun $ip $passwd   &>/dev/null
	}&
	done 
	wait 
}
[ "$SET_RS" == "ON" ]&& set_rs  
# 配置服务

case "$1" in
start)
  	if [ "$mod" == "g" ];then
  		#DR配置绑定VIP
  		ifconfig $interface $VIP broadcast $VIP netmask 255.255.255.255 up
  		#添加主机路由
  		route add -host $VIP dev $interface
  	elif [ "$mod" == "n"  ];then         
  	#配置网卡转发
  		echo 1 > /proc/sys/net/ipv4/ip_forward
  	fi
  #判断安装ipvsadm
  rpm -qa|grep ipvsadm >> /dev/null
  if [ $? -ne 0 ];then
      yum -y install ipvsadm
  fi
  #清空lvs规则
  ipvsadm -C
  #添加一个转发服务  
  ipvsadm -A -t $VIP:$port -s $policy
  #添加分发节点
  for RIP in ${!RIPS[*]}
  do
      ipvsadm -a -t $VIP:$port -r $RIP -$mod
  done
   ipvsadm -Ln 
;; 
  
stop)
	if [ "$mod" == "g"  ];then
		ifconfig $interface down
	elif [ "$mod" == "n"  ];then
  		#关闭网卡转发
	  	echo 0 > /proc/sys/net/ipv4/ip_forward
	fi
  	#清空lvs规则
  	ipvsadm -C
  	echo
  	ipvsadm -Ln
;;
status)
  #查看当前规则
  ipvsadm -Ln
  echo
;; 
RS) set_rs ;; 
*) 
  echo "Usage: $0 {start|stop|status|gw}"
;; esac
