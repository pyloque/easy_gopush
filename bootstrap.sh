vmname=$1
step=$2
vmindex=${vmname#zhangyue}
zookeeper_home=/usr/local/zookeeper
go_home=/usr/local/go
go_path=~/go
pid_dir=/tmp/pids

function install_pkgs()
{
    sudo apt-get update -qqy
    sudo apt-get install -qqy openjdk-7-jdk
    sudo apt-get install -qqy redis-server
    sudo apt-get install -qqy mercurial
    sudo apt-get install -qqy git
    if [ ! -d $zookeeper_home ]
    then
        wget -nc -q -P /var/cache/wget http://mirror.nus.edu.sg/apache/zookeeper/stable/zookeeper-3.4.6.tar.gz
        tar xvf /var/cache/wget/zookeeper-3.4.6.tar.gz -C ~ > /dev/null
        sudo mv zookeeper-3.4.6 $zookeeper_home
    fi
    if [ ! -d $go_home ]
    then
        wget -nc -q -P /var/cache/wget https://storage.googleapis.com/golang/go1.3.linux-amd64.tar.gz
        tar xvf /var/cache/wget/go1.3.linux-amd64.tar.gz -C ~ > /dev/null
        sudo mv go $go_home
    fi
}

function write_hosts()
{
    touch /tmp/hosts
    if ! grep "master" /etc/hosts > /dev/null
    then
    cat /etc/hosts > /tmp/hosts
    sed -i '/zhangyue/d' /tmp/hosts
    cat << EOF >> /tmp/hosts
172.28.2.10 master zhangyue0
172.28.2.11 slave1 zhangyue1
172.28.2.12 slave2 zhangyue2
EOF
    sudo cp /tmp/hosts /etc/hosts
    fi
}

function write_zk()
{
    mkdir -p ~/zkdata
    echo $vmindex > ~/zkdata/myid
    cd $zookeeper_home
    cat << EOF > conf/zoo.cfg
tickTime=2000
dataDir=/home/vagrant/zkdata
clientPort=2181
initLimit=5
syncLimit=2
server.0=zhangyue0:2888:3888
server.1=zhangyue1:2888:3888
server.2=zhangyue2:2888:3888
EOF
}

function write_redis()
{
    sudo sed -i "s/bind 127.0.0.1/bind 0.0.0.0/g" /etc/redis/redis.conf
    sudo service redis-server restart
}

function start_zk()
{
    cd $zookeeper_home
    bin/zkServer.sh restart
}

function write_bashrc()
{

    if ! grep "GOROOT" ~/.bashrc > /dev/null
    then
    cat << EOF >> ~/.bashrc
export GOROOT=/usr/local/go
export PATH=$PATH:\$GOROOT/bin
export GOPATH=~/go
EOF
    fi
    cat << EOF > /tmp/goenv.sh
export GOROOT=/usr/local/go
export PATH=$PATH:\$GOROOT/bin
export GOPATH=~/go
EOF
    mkdir -p ~/go
}

function install_gopush()
{
    cd ~
    source /tmp/goenv.sh
    if [ ! -f $go_path/bin/message ]
    then
        wget -nc -q https://raw.githubusercontent.com/Terry-Mao/gopush-cluster/master/dependencies.sh
        bash ~/dependencies.sh
        mkdir -p $go_path/conf
        gopush_src=$go_path/src/github.com/Terry-Mao/gopush-cluster
        cd $gopush_src/message
        go install
        cp message-example.conf $go_path/conf/message.conf
        cp log.xml $go_path/conf/message_log.xml
        cd $gopush_src/comet
        go install
        cp comet-example.conf $go_path/conf/comet.conf
        cp log.xml $go_path/conf/comet_log.xml
        cd $gopush_src/web
        go install
        cp web-example.conf $go_path/conf/web.conf
        cp log.xml $go_path/conf/web_log.xml
    fi
}

function write_gopush()
{
    command="s/addr localhost:2181/addr zhangyue0:2181,zhangyue1:2181,zhangyue2:2181/g"
    sed -i "$command" $go_path/conf/message.conf
    sed -i "$command" $go_path/conf/comet.conf
    sed -i "$command" $go_path/conf/web.conf
    command="s/\/data\/apps\/go\/bin/\/home\/vagrant\/go\/conf/g"
    sed -i "$command" $go_path/conf/message.conf
    sed -i "$command" $go_path/conf/comet.conf
    sed -i "$command" $go_path/conf/web.conf
    sed -i $'s/node1:1 tcp@localhost/node1:1 tcp@zhangyue0\\\nnode2:1 tcp@zhangyue1\\\nnode3:1 tcp@zhangyue2/g' $go_path/conf/message.conf
    sed -i "s/localhost/$vmname/g" $go_path/conf/message.conf
    sed -i "s/localhost/$vmname/g" $go_path/conf/comet.conf
    sed -i "s/localhost/$vmname/g" $go_path/conf/web.conf
    command="s/comet\.node node1/comet\.node $vmname/g"
    sed -i "$command" $go_path/conf/comet.conf
}

function start_gopush()
{
    
    gopush_logs=$go_path/logs/gopush-cluster
    mkdir -p $gopush_logs 
    mkdir -p $pid_dir/gopush
    if [ -f $pid_dir/gopush/message.pid ]
    then
        kill -TERM $(cat $pid_dir/gopush/message.pid)
        sleep 2
    fi
    nohup $go_path/bin/message -c $go_path/conf/message.conf 2>&1 >> $gopush_logs/panic-message.log &
    echo $! > $pid_dir/gopush/message.pid
    if [ -f $pid_dir/gopush/comet.pid ]
    then
        kill -TERM $(cat $pid_dir/gopush/comet.pid)
        sleep 2
    fi
    nohup $go_path/bin/comet -c $go_path/conf/comet.conf 2>&1 >> $gopush_logs/panic-comet.log &
    echo $! > $pid_dir/gopush/comet.pid
    if [ -f $pid_dir/gopush/web.pid ]
    then
        kill -TERM $(cat $pid_dir/gopush/web.pid)
        sleep 2
    fi
    nohup $go_path/bin/web -c $go_path/conf/web.conf 2>&1 >> $gopush_logs/panic-web.log &
    echo $! > $pid_dir/gopush/web.pid
}

function setup_vim()
{
    if [ ! -d ~/.vim/bundle/Vundle.vim ]
    then
        git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    fi
    cat << EOF > ~/.vimrc
set nobackup
set tabstop=4
set sw=4
set expandtab
set ruler
set hlsearch
set incsearch
set showmatch
set nu
set ai
set si
set fenc=utf-8
set fencs=utf-8,gbk,gb2312
set mouse=a
set cursorline
syntax on

set nocompatible
filetype off
set rtp+=~/.vim/bundle/Vundle.vim/
call vundle#begin()
Bundle 'gmarik/Vundle.vim'
Bundle 'scrooloose/nerdtree'
Bundle 'fatih/vim-go'
call vundle#end()

filetype plugin indent on

map <F2> :noh<CR>
map <F5> :NERDTreeToggle<Cr>
map <F6> :tabnew<CR>
map <F7> :split<CR>
map <F8> :vsplit<CR>

let Tlist_Exit_OnlyWindow=1 
let NERDTreeDirArrows=0
EOF
vim +PluginInstall +qall > /dev/null
}

function setup()
{
    install_pkgs
    write_hosts
    write_zk
    start_zk
    write_redis
    write_bashrc
    install_gopush
    write_gopush
    setup_vim
}

function start()
{
    start_gopush
}

if [ "$step" -eq 0 ]
then
    setup
elif [ "$step" -eq 1 ]
then
    start
fi
