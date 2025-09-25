#!/usr/bin/env bash
#=============================================================
# https://github.com/WizisCool/SSH_Key_Installer
# 描述: 通过GitHub、URL或本地文件安装SSH密钥
# 版本: 3.0 修复增强版
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
        echo -e "${INFO} 创建 ${HOME}/.ssh/authorized_keys..."
        mkdir -p ${HOME}/.ssh/
        touch ${HOME}/.ssh/authorized_keys
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

enable_pubkey_auth() {
    echo -e "${INFO} 正在确保密钥认证已启用..."
    
    if [ $(uname -o) == Android ]; then
        SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
        SED_CMD="sed -i"
    else
        SSHD_CONFIG="/etc/ssh/sshd_config"
        SED_CMD="$SUDO sed -i"
    fi
    
    # 备份配置文件
    if [ $(uname -o) == Android ]; then
        cp $SSHD_CONFIG ${SSHD_CONFIG}.bak
    else
        $SUDO cp $SSHD_CONFIG ${SSHD_CONFIG}.bak
    fi
    
    # 处理PubkeyAuthentication - 使用更精确的sed命令
    if grep -q "^PubkeyAuthentication" $SSHD_CONFIG 2>/dev/null; then
        # 如果存在未注释的行，直接修改为yes
        $SED_CMD 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSHD_CONFIG
    elif grep -q "^#PubkeyAuthentication" $SSHD_CONFIG 2>/dev/null; then
        # 如果存在注释的行，取消注释并设为yes
        $SED_CMD 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSHD_CONFIG
    else
        # 如果完全不存在，添加到文件末尾
        if [ $(uname -o) == Android ]; then
            echo "PubkeyAuthentication yes" >> $SSHD_CONFIG
        else
            echo "PubkeyAuthentication yes" | $SUDO tee -a $SSHD_CONFIG > /dev/null
        fi
    fi
    
    # 确保AuthorizedKeysFile配置存在
    if ! grep -q "^AuthorizedKeysFile" $SSHD_CONFIG 2>/dev/null; then
        if [ $(uname -o) == Android ]; then
            echo "AuthorizedKeysFile .ssh/authorized_keys" >> $SSHD_CONFIG
        else
            echo "AuthorizedKeysFile .ssh/authorized_keys" | $SUDO tee -a $SSHD_CONFIG > /dev/null
        fi
    fi
    
    echo -e "${INFO} 密钥认证配置完成"
    RESTART_SSHD=1
}

test_config() {
    # 仅在非Android系统上测试配置
    if [ $(uname -o) != Android ]; then
        if [ $(uname -o) == Android ]; then
            SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
        else
            SSHD_CONFIG="/etc/ssh/sshd_config"
        fi
        
        $SUDO sshd -t -f $SSHD_CONFIG 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} SSH配置文件有错误，正在恢复..."
            $SUDO cp ${SSHD_CONFIG}.bak $SSHD_CONFIG
            exit 1
        fi
    fi
}

change_port() {
    echo -e "${INFO} 正在将SSH端口更改为 ${SSH_PORT} ..."
    if [ $(uname -o) == Android ]; then
        if grep -q "^Port " "$PREFIX/etc/ssh/sshd_config"; then
            sed -i "s/^Port .*/Port ${SSH_PORT}/" $PREFIX/etc/ssh/sshd_config
        elif grep -q "^#Port " "$PREFIX/etc/ssh/sshd_config"; then
            sed -i "s/^#Port .*/Port ${SSH_PORT}/" $PREFIX/etc/ssh/sshd_config
        else
            echo "Port ${SSH_PORT}" >> $PREFIX/etc/ssh/sshd_config
        fi
        echo -e "${INFO} SSH端口更改成功！"
        RESTART_SSHD=2
    else
        if grep -q "^Port " /etc/ssh/sshd_config; then
            $SUDO sed -i "s/^Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
        elif grep -q "^#Port " /etc/ssh/sshd_config; then
            $SUDO sed -i "s/^#Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
        else
            echo "Port ${SSH_PORT}" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        fi
        echo -e "${INFO} SSH端口更改成功！"
        RESTART_SSHD=1
    fi
}

disable_password() {
    echo -e "${WARNING} 禁用密码登录前，请确保您能使用密钥登录！"
    echo -e "${INFO} 建议先在新窗口测试密钥登录是否正常"
    read -p "继续禁用密码登录吗？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${INFO} 已取消"
        return
    fi
    
    if [ $(uname -o) == Android ]; then
        if grep -q "^PasswordAuthentication" $PREFIX/etc/ssh/sshd_config; then
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' $PREFIX/etc/ssh/sshd_config
        elif grep -q "^#PasswordAuthentication" $PREFIX/etc/ssh/sshd_config; then
            sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' $PREFIX/etc/ssh/sshd_config
        else
            echo "PasswordAuthentication no" >> $PREFIX/etc/ssh/sshd_config
        fi
        RESTART_SSHD=2
    else
        if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
            $SUDO sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        elif grep -q "^#PasswordAuthentication" /etc/ssh/sshd_config; then
            $SUDO sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        else
            echo "PasswordAuthentication no" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        fi
        RESTART_SSHD=1
    fi
    echo -e "${INFO} 已禁用SSH密码登录"
}

# 主程序逻辑
KEY_INSTALLED=0

while getopts "og:u:f:p:d" OPT; do
    case $OPT in
    o)
        OVERWRITE=1
        ;;
    g)
        KEY_ID=$OPTARG
        get_github_key
        install_key
        KEY_INSTALLED=1
        ;;
    u)
        KEY_URL=$OPTARG
        get_url_key
        install_key
        KEY_INSTALLED=1
        ;;
    f)
        KEY_PATH=$OPTARG
        get_loacl_key
        install_key
        KEY_INSTALLED=1
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

# 如果安装了密钥，自动启用密钥认证
if [ "$KEY_INSTALLED" = 1 ]; then
    enable_pubkey_auth
    test_config
fi

# 处理重启
if [ "$RESTART_SSHD" = 1 ]; then
    echo -e "${WARNING} 即将重启SSH服务，请确保您有备用连接方式"
    echo -e "${INFO} 建议先在新窗口测试连接"
    
    # 检测SSH服务名称
    if systemctl list-units --full -all | grep -q "ssh.service"; then
        SSH_SERVICE="ssh"
    elif systemctl list-units --full -all | grep -q "sshd.service"; then
        SSH_SERVICE="sshd"
    else
        # 尝试查找其他可能的SSH服务名
        SSH_SERVICE=$(systemctl list-units --full -all | grep -E "(ssh|sshd)" | grep ".service" | head -1 | awk '{print $1}' | sed 's/.service//')
    fi
    
    if [ -n "$SSH_SERVICE" ]; then
        $SUDO systemctl restart ${SSH_SERVICE} && echo -e "${INFO} SSH服务已重启"
    else
        echo -e "${WARNING} 无法自动检测SSH服务名称"
        echo -e "${INFO} 请手动重启SSH服务："
        echo -e "  ${INFO} 尝试: sudo systemctl restart ssh"
        echo -e "  ${INFO} 或者: sudo systemctl restart sshd"
        echo -e "  ${INFO} 或者: sudo service ssh restart"
    fi
elif [ "$RESTART_SSHD" = 2 ]; then
    echo -e "${INFO} 请重启sshd服务或Termux应用以使更改生效"
fi

echo -e "${INFO} 操作完成！"
