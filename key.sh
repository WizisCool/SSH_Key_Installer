#!/usr/bin/env bash
#=============================================================
# https://github.com/wiziscool/SSH_Key_Installer
# 描述: 通过GitHub、URL或本地文件安装SSH密钥
# 版本: 3.0 (改进版)
# 作者: WizisCool 
# 博客: https://dooo.ng
#=============================================================

VERSION=2.8
RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[33m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}信息${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}错误${FONT_COLOR_SUFFIX}]"
WARNING="[${YELLOW_FONT_PREFIX}警告${FONT_COLOR_SUFFIX}]"
[ $EUID != 0 ] && SUDO=sudo

USAGE() {
    echo "
SSH密钥安装程序 $VERSION

用法:
  bash <(curl -fsSL git.io/key.sh) [选项...] <参数>

选项:
  -o	覆盖模式，此选项在最前面有效
  -g	从GitHub获取公钥，参数为GitHub ID
  -u	从URL获取公钥，参数为URL地址
  -f	从本地文件获取公钥，参数为本地文件路径
  -p	更改SSH端口，参数为端口号
  -d	禁用密码登录"
}

if [ $# -eq 0 ]; then
    USAGE
    exit 1
fi

get_github_key() {
    if [ "${KEY_ID}" == '' ]; then
        read -e -p "请输入GitHub账号: " KEY_ID
        [ "${KEY_ID}" == '' ] && echo -e "${ERROR} 输入无效。" && exit 1
    fi
    echo -e "${INFO} GitHub账号是: ${KEY_ID}"
    echo -e "${INFO} 正在从GitHub获取密钥..."
    PUB_KEY=$(curl -fsSL https://github.com/${KEY_ID}.keys)
    if [ "${PUB_KEY}" == 'Not Found' ]; then
        echo -e "${ERROR} GitHub账号未找到。"
        exit 1
    elif [ "${PUB_KEY}" == '' ]; then
        echo -e "${ERROR} 该账号没有SSH密钥。"
        exit 1
    fi
}

get_url_key() {
    if [ "${KEY_URL}" == '' ]; then
        read -e -p "请输入URL地址: " KEY_URL
        [ "${KEY_URL}" == '' ] && echo -e "${ERROR} 输入无效。" && exit 1
    fi
    echo -e "${INFO} 正在从URL获取密钥..."
    PUB_KEY=$(curl -fsSL ${KEY_URL})
}

get_loacl_key() {
    if [ "${KEY_PATH}" == '' ]; then
        read -e -p "请输入文件路径: " KEY_PATH
        [ "${KEY_PATH}" == '' ] && echo -e "${ERROR} 输入无效。" && exit 1
    fi
    echo -e "${INFO} 正在从 ${KEY_PATH} 获取密钥..."
    PUB_KEY=$(cat ${KEY_PATH})
}

install_key() {
    [ "${PUB_KEY}" == '' ] && echo "${ERROR} SSH密钥不存在。" && exit 1
    if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
        echo -e "${INFO} '${HOME}/.ssh/authorized_keys' 文件不存在..."
        echo -e "${INFO} 正在创建 ${HOME}/.ssh/authorized_keys..."
        mkdir -p ${HOME}/.ssh/
        touch ${HOME}/.ssh/authorized_keys
        if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
            echo -e "${ERROR} 创建SSH密钥文件失败。"
        else
            echo -e "${INFO} 密钥文件创建成功，继续进行..."
        fi
    fi
    if [ "${OVERWRITE}" == 1 ]; then
        echo -e "${INFO} 正在覆盖SSH密钥..."
        echo -e "${PUB_KEY}\n" >${HOME}/.ssh/authorized_keys
    else
        echo -e "${INFO} 正在添加SSH密钥..."
        echo -e "\n${PUB_KEY}\n" >>${HOME}/.ssh/authorized_keys
    fi
    chmod 700 ${HOME}/.ssh/
    chmod 600 ${HOME}/.ssh/authorized_keys
    [[ $(grep "${PUB_KEY}" "${HOME}/.ssh/authorized_keys") ]] &&
        echo -e "${INFO} SSH密钥安装成功！" || {
        echo -e "${ERROR} SSH密钥安装失败！"
        exit 1
    }
}

check_and_enable_pubkey_auth() {
    echo -e "${INFO} 正在检查密钥认证状态..."
    
    if [ $(uname -o) == Android ]; then
        SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
    else
        SSHD_CONFIG="/etc/ssh/sshd_config"
    fi
    
    # 备份配置文件
    if [ $(uname -o) == Android ]; then
        cp $SSHD_CONFIG ${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)
    else
        $SUDO cp $SSHD_CONFIG ${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)
    fi
    echo -e "${INFO} 配置文件已备份"
    
    # 检查并启用密钥认证
    if grep -q "^PubkeyAuthentication no" $SSHD_CONFIG 2>/dev/null || grep -q "^#PubkeyAuthentication" $SSHD_CONFIG 2>/dev/null; then
        echo -e "${WARNING} 密钥认证未启用，正在启用..."
        if [ $(uname -o) == Android ]; then
            sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSHD_CONFIG
        else
            $SUDO sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSHD_CONFIG
        fi
        echo -e "${INFO} 密钥认证已启用"
        RESTART_SSHD=1
    elif grep -q "^PubkeyAuthentication yes" $SSHD_CONFIG 2>/dev/null; then
        echo -e "${INFO} 密钥认证已经启用"
    else
        # 如果没有找到相关配置，添加配置
        echo -e "${WARNING} 未找到密钥认证配置，正在添加..."
        if [ $(uname -o) == Android ]; then
            echo "PubkeyAuthentication yes" >> $SSHD_CONFIG
        else
            echo "PubkeyAuthentication yes" | $SUDO tee -a $SSHD_CONFIG > /dev/null
        fi
        echo -e "${INFO} 密钥认证配置已添加"
        RESTART_SSHD=1
    fi
    
    # 确保AuthorizedKeysFile配置正确
    if ! grep -q "^AuthorizedKeysFile" $SSHD_CONFIG 2>/dev/null; then
        echo -e "${INFO} 添加AuthorizedKeysFile配置..."
        if [ $(uname -o) == Android ]; then
            echo "AuthorizedKeysFile .ssh/authorized_keys" >> $SSHD_CONFIG
        else
            echo "AuthorizedKeysFile .ssh/authorized_keys" | $SUDO tee -a $SSHD_CONFIG > /dev/null
        fi
    fi
}

test_ssh_connection() {
    echo -e "${INFO} 正在测试SSH密钥连接..."
    
    # 获取当前SSH端口
    if [ $(uname -o) == Android ]; then
        SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
    else
        SSHD_CONFIG="/etc/ssh/sshd_config"
    fi
    
    CURRENT_PORT=$(grep "^Port " $SSHD_CONFIG 2>/dev/null | awk '{print $2}')
    [ -z "$CURRENT_PORT" ] && CURRENT_PORT=22
    
    # 测试配置文件语法
    if [ $(uname -o) != Android ]; then
        echo -e "${INFO} 检查SSH配置文件语法..."
        $SUDO sshd -t -f $SSHD_CONFIG
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} SSH配置文件存在语法错误！"
            echo -e "${WARNING} 正在恢复备份配置..."
            $SUDO cp ${SSHD_CONFIG}.bak.$(ls -t ${SSHD_CONFIG}.bak.* | head -1 | cut -d. -f4) $SSHD_CONFIG
            exit 1
        fi
        echo -e "${INFO} SSH配置文件语法检查通过"
    fi
    
    echo -e "${INFO} SSH密钥配置完成"
    echo -e "${WARNING} 请确保在重启SSHD服务前，您能够使用密钥连接到服务器"
    echo -e "${INFO} 当前SSH端口: ${CURRENT_PORT}"
    
    if [ "$DISABLE_PASSWORD" != 1 ]; then
        echo -e "${WARNING} 建议先测试密钥连接是否正常，确认后再禁用密码登录"
    fi
}

change_port() {
    echo -e "${INFO} 正在将SSH端口更改为 ${SSH_PORT} ..."
    if [ $(uname -o) == Android ]; then
        [[ -z $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] &&
            echo -e "Port ${SSH_PORT}" >>$PREFIX/etc/ssh/sshd_config ||
            sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" $PREFIX/etc/ssh/sshd_config
        [[ $(grep "Port " "$PREFIX/etc/ssh/sshd_config") ]] && {
            echo -e "${INFO} SSH端口更改成功！"
            RESTART_SSHD=2
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH端口更改失败！"
            exit 1
        }
    else
        $SUDO sed -i "s@.*\(Port \).*@\1${SSH_PORT}@" /etc/ssh/sshd_config && {
            echo -e "${INFO} SSH端口更改成功！"
            RESTART_SSHD=1
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} SSH端口更改失败！"
            exit 1
        }
    fi
}

disable_password() {
    DISABLE_PASSWORD=1
    echo -e "${WARNING} 准备禁用密码登录..."
    echo -e "${INFO} 请先确认您已经能够使用密钥成功连接"
    read -p "您确认已经测试过密钥连接并且能够正常登录吗？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${WARNING} 已取消禁用密码登录，请先测试密钥连接"
        return
    fi
    
    if [ $(uname -o) == Android ]; then
        sed -i "s@.*\(PasswordAuthentication \).*@\1no@" $PREFIX/etc/ssh/sshd_config && {
            RESTART_SSHD=2
            echo -e "${INFO} 已禁用SSH密码登录。"
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} 禁用密码登录失败！"
            exit 1
        }
    else
        $SUDO sed -i "s@.*\(PasswordAuthentication \).*@\1no@" /etc/ssh/sshd_config && {
            RESTART_SSHD=1
            echo -e "${INFO} 已禁用SSH密码登录。"
        } || {
            RESTART_SSHD=0
            echo -e "${ERROR} 禁用密码登录失败！"
            exit 1
        }
    fi
}

while getopts "og:u:f:p:d" OPT; do
    case $OPT in
    o)
        OVERWRITE=1
        ;;
    g)
        KEY_ID=$OPTARG
        get_github_key
        install_key
        check_and_enable_pubkey_auth
        test_ssh_connection
        ;;
    u)
        KEY_URL=$OPTARG
        get_url_key
        install_key
        check_and_enable_pubkey_auth
        test_ssh_connection
        ;;
    f)
        KEY_PATH=$OPTARG
        get_loacl_key
        install_key
        check_and_enable_pubkey_auth
        test_ssh_connection
        ;;
    p)
        SSH_PORT=$OPTARG
        change_port
        ;;
    d)
        disable_password
        ;;
    ?)
        USAGE
        exit 1
        ;;
    :)
        USAGE
        exit 1
        ;;
    *)
        USAGE
        exit 1
        ;;
    esac
done

if [ "$RESTART_SSHD" = 1 ]; then
    echo -e "${INFO} 正在重启sshd服务..."
    echo -e "${WARNING} 请确保您有其他方式访问服务器，以防连接失败"
    read -p "您确认要重启SSH服务吗？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $SUDO systemctl restart sshd && echo -e "${INFO} 完成。"
    else
        echo -e "${WARNING} 已取消重启SSH服务"
        echo -e "${INFO} 配置已保存，但需要手动重启SSH服务才能生效"
        echo -e "${INFO} 使用命令: sudo systemctl restart sshd"
    fi
elif [ "$RESTART_SSHD" = 2 ]; then
    echo -e "${INFO} 请重启sshd服务或Termux应用以使更改生效。"
fi

echo -e "\n${INFO} 操作完成！"
echo -e "${INFO} 请保持当前SSH连接，并在新窗口中测试密钥登录是否正常"
