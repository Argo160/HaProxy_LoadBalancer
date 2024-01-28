#!/bin/bash

check_haproxy_availability() {
    if command -v haproxy &>/dev/null; then
        return 0  # HAProxy is installed
    else
        return 1  # HAProxy is not installed
    fi
}

install_haproxy() {
    if check_haproxy_availability; then
        echo "HAProxy is already installed."
    else
        # Install HAProxy
        echo "Installing HAProxy..."
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update
            sudo apt-get install -y haproxy
            apt install curl socat -y
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y haproxy
        else
            echo "Unsupported package manager. Cannot install HAProxy."
            exit 1
        fi

        # Check installation status
        if [ $? -eq 0 ]; then
                # Backup the original configuration file (optional)
                cp "/etc/haproxy/haproxy.cfg" "/etc/haproxy/haproxy.cfg.bak"

                # Replace the original configuration file with the new one
                # Download the haproxy.cfg from GitHub and overwrite the original file
                wget -O /etc/haproxy/haproxy.cfg https://raw.githubusercontent.com/Argo160/HaProxy_LoadBalancer/main/haproxy.cfg
               echo "HAProxy configuration file replaced successfully."
            echo "HAProxy installed successfully."
        else
            echo "Failed to install HAProxy."
            exit 1
        fi
    fi
}

uninstall_haproxy() {
    if check_haproxy_availability; then
        # Uninstall HAProxy
        echo "Uninstalling HAProxy..."
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get remove --purge -y haproxy
        elif [ -x "$(command -v yum)" ]; then
            sudo yum remove -y haproxy
        else
            echo "Unsupported package manager. Cannot uninstall HAProxy."
            exit 1
        fi

        # Check uninstallation status
        if [ $? -eq 0 ]; then
            echo "HAProxy uninstalled successfully."
        else
            echo "Failed to uninstall HAProxy."
            exit 1
        fi
    else
        echo "HAProxy is not installed."
    fi
}
#               # Verify the updated HAProxy configuration for any syntax errors
#               haproxy -c -f "$config_file"

#               # Reload HAProxy to apply the changes
#               systemctl reload haproxy

is_ipv4_or_ipv6() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 4  # IPv4
    elif [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 6  # IPv6
    else
        return 0  # Not IPv4 or IPv6
    fi
}

add_ip() {
    # Check if at least one port is specified in both backend and frontend sections
    config_file="/etc/haproxy/haproxy.cfg"
#    if ! grep -qE "^\s*server\s+\w+\s+\d+\.\d+\.\d+\.\d+:[0-9]+\s*$" "$config_file"; then
    if ! grep -qE '^ *bind \*:[0-9]+' "$config_file"; then
        echo "Please specify at least one port in the HAProxy configuration file before adding IP addresses."
        return
    fi
    # Extract unique IPv4 addresses
    ipv4_addresses=$(grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$config_file" | sort -u)
    # Extract unique IPv6 addresses
    ipv6_addresses=$(grep -E 'server.*\[[^]]+\]' "$config_file" | awk -F'[][]' '{print $2}' | sort | uniq)
    # Print the extracted addresses
    clear
    echo -e "\e[1mCurrent IPv4 addresses:\e[0m"
    echo -e "\e[33m$ipv4_addresses\e[0m"
    echo -e "\e[1mCurrent IPv6 addresses:\e[0m"
    echo -e "\e[33m$ipv6_addresses\e[0m"
    read -p "Enter the IP address to add: " ip_address
    if grep -q "$ip_address" "$config_file"; then
        echo "The IP address $ip_address already exists in the configuration file."
    else
        # Call the function and pass the IP address
        is_ipv4_or_ipv6 "$ip_address"

        # Check the return value
        case $? in
        4)
            echo "Adding IPv4 address $ip_address to HAProxy configuration..."
            # Extract ports from the HAProxy configuration file
            total_ports=$(grep -E '^ *bind \*:([0-9]+)$' "$config_file" | awk -F: '{print $2}')
            if grep -qE '^\s*server .* check send-proxy-v2$' "$config_file"; then
                for portt in $total_ports; do
                    # Assign the first port from the list to the current IP address
                    sed -i '/option tcp-check/a\    server server_'"$ip_address"'-'"$portt"' '"$ip_address"':'"$portt"' check send-proxy-v2' "$config_file"
                done
            else
                for portt in $total_ports; do
                    # Assign the first port from the list to the current IP address
                    sed -i '/option tcp-check/a\    server server_'"$ip_address"'-'"$portt"' '"$ip_address"':'"$portt"' check' "$config_file"
                done
            fi
            systemctl restart haproxy
            echo "IPv4 address $ip_address added successfully."
            ;;
        6)
            echo "Adding IPv6 address $ip_address to HAProxy configuration..."
            # Extract ports from the HAProxy configuration file
            total_ports=$(grep -E '^ *bind \*:([0-9]+)$' "$config_file" | awk -F: '{print $2}')
            if grep -qE '^\s*server .* check send-proxy-v2$' "$config_file"; then
                for portt in $total_ports; do
                    # Assign the first port from the list to the current IP address
                    sed -i '/option tcp-check/a\    server server_'"$ip_address"'-'"$portt"' ['"$ip_address"']:'"$portt"' check send-proxy-v2' "$config_file"
                done
            else
                for portt in $total_ports; do
                    # Assign the first port from the list to the current IP address
                    sed -i '/option tcp-check/a\    server server_'"$ip_address"'-'"$portt"' ['"$ip_address"']:'"$portt"' check' "$config_file"
                done
            fi
            # Add the IPv6 address to HAProxy configuration here
            echo "IPv6 address [$ip_address] added successfully."
            systemctl restart haproxy
            ;;
        *)
            echo "Not an IPv4 or IPv6 address."
            ;;
        esac
    fi
}

remove_ip() {
    config_file="/etc/haproxy/haproxy.cfg"
    # Extract unique IPv4 addresses
    ipv4_addresses=$(grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$config_file" | sort -u)
    # Extract unique IPv6 addresses
    ipv6_addresses=$(grep -E 'server.*\[[^]]+\]' "$config_file" | awk -F'[][]' '{print $2}' | sort | uniq)
    # Print the extracted addresses
    clear
    echo -e "\e[1mCurrent IPv4 addresses:\e[0m"
    echo -e "\e[33m$ipv4_addresses\e[0m"
    echo -e "\e[1mCurrent IPv6 addresses:\e[0m"
    echo -e "\e[33m$ipv6_addresses\e[0m"
    read -p "Enter the IP address to be removed: " ip_address
    if grep -q "$ip_address" "$config_file"; then
        echo "The IP address $ip_address is being removed from the configuration file."
        ip_to_delete="$ip_address"

        # Update backend configuration
        sed -i "/^ *server .*${ip_to_delete}\]:/d" "$config_file"
        systemctl restart haproxy
        echo "IPv4 address $ip_address removed successfully."
     else
        echo "The IP address $ip_address Does not Exists in HAProxy configuration..."
    fi
}

add_port() {
    config_file="/etc/haproxy/haproxy.cfg"
    current_ports=$(awk '/^frontend vpn_frontend/{flag=1; next} /^default_backend/{flag=0} flag && /bind \*:/{print $2}' "$config_file" | cut -d ':' -f 2)
    clear
    echo -e "\e[1mCurrent Ports::\e[0m"
    echo -e "\e[33m$current_ports\e[0m"

    read -p "Enter the port to add: " port
        # Check if the port exists in the frontend section of the configuration file
        if grep -q "bind.*:$port\b" "$config_file"; then
            echo "Port $port is already configured in the frontend section of $config_file"
        else
            echo "Adding port $port to HAProxy configuration..."
            # Path to the HAProxy configuration file
            sed -i '/frontend vpn_frontend/a\    bind *:'"$port"'' "$config_file"
            #echo "Added 'bind *:$port' after 'mode tcp' in the frontend section of $config_file"
            if grep -qE '^\s*server .* check send-proxy-v2$' "$config_file"; then
                # Extract unique IPv4 addresses
                ipv4_addresses=$(grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$config_file" | sort -u)
                if [ -n "$ipv4_addresses" ]; then
                    for ip in $ipv4_addresses; do
                        sed -i '/option tcp-check/a\    server server_'"$ip"'-'"$port"' '"$ip"':'"$port"' check send-proxy-v2' "$config_file"
                    done
                    systemctl restart haproxy
                fi
                # Extract unique IPv6 addresses
                ipv6_addresses=$(grep -E 'server.*\[[^]]+\]' "$config_file" | awk -F'[][]' '{print $2}' | sort | uniq)
                if [ -n "$ipv6_addresses" ]; then
                   for ip in $ipv6_addresses; do
                       sed -i '/option tcp-check/a\    server server_'"$ip"'-'"$port"' ['"$ip"']:'"$port"' check send-proxy-v2' "$config_file"
                   done
                   systemctl restart haproxy
                fi       
            else
                # Extract unique IPv4 addresses
                ipv4_addresses=$(grep -Eo '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$config_file" | sort -u)
                if [ -n "$ipv4_addresses" ]; then
                    for ip in $ipv4_addresses; do
                        sed -i '/option tcp-check/a\    server server_'"$ip"'-'"$port"' '"$ip"':'"$port"' check' "$config_file"
                    done
                    systemctl restart haproxy
                fi
                # Extract unique IPv6 addresses
                ipv6_addresses=$(grep -E 'server.*\[[^]]+\]' "$config_file" | awk -F'[][]' '{print $2}' | sort | uniq)
                if [ -n "$ipv6_addresses" ]; then
                   for ip in $ipv6_addresses; do
                       sed -i '/option tcp-check/a\    server server_'"$ip"'-'"$port"' ['"$ip"']:'"$port"' check' "$config_file"
                   done
                   systemctl restart haproxy
                fi       
            fi
     fi
}

remove_port() {
    config_file="/etc/haproxy/haproxy.cfg"
    current_ports=$(awk '/^frontend vpn_frontend/{flag=1; next} /^default_backend/{flag=0} flag && /bind \*:/{print $2}' "$config_file" | cut -d ':' -f 2)
    clear
    echo -e "\e[1mCurrent Ports::\e[0m"
    echo -e "\e[33m$current_ports\e[0m"

    read -p "Enter the port to remove: " port
        # Check if the port exists in the frontend section of the configuration file
        if grep -q "bind.*:$port\b" "$config_file"; then
            echo "Port $port is being deleted from HAProxy configuration..."
            # Define the port to be deleted
            port_to_delete="$port"
            # Update frontend configuration
            sed -i "/^ *bind .*:$port_to_delete$/d" "$config_file"
            # Update backend configuration
            sed -i "/^ *server .*:$port_to_delete/d" "$config_file"
            systemctl restart haproxy
            echo "Port $port removed successfully."
        else
            echo "The port $port Does not Exists in HAProxy configuration..."
        fi
}
health_check() {
server_info=$(echo "show stat" | socat stdio /run/haproxy/admin.sock | awk -F',' '/^vpn_backend,/ && !/BACKEND/{print $2,$18}')

# Checking each server's status
echo "$server_info" | while read -r server_ip status; do
    if [[ "$status" == "UP" ]]; then
        echo -e "\e[32mServer at $server_ip is up.\e[0m"  # Green color for UP
    else
        echo -e "\e[31mServer at $server_ip is down.\e[0m"  # Red color for DOWN
    fi
done
}
proxy_protocol() {
    clear
    config_file="/etc/haproxy/haproxy.cfg"
#    if ! grep -qE '^ *server .* check$' "$config_file"; then
#        echo "Atleast one ip address is required in configuration file"
#    else
#        if grep -qE '^\s*server .* check send-proxy-v2$' "$config_file"; then
#            echo -e "\e[32mProxy Protocol is Enabled.\e[0m"  # Green color for Enabled
#            read -p "Do you want to Disable it? (y/n): " pp
#            # Convert input to lowercase
#            pp_lowercase=$(echo "$pp" | tr '[:upper:]' '[:lower:]')
#            # Check if the input is "y"
#            if [ "$pp_lowercase" = "y" ]; then
#                # Tasks to be performed if input is "y"
#                sed -i 's/send-proxy-v2//g' "$config_file"
#            fi
#        else
#            echo -e "\e[33mProxy Protocol is Disabled.\e[0m"
#            read -p "Do you want to Enable it? (y/n): " pp    
#            # Convert input to lowercase
#            pp_lowercase=$(echo "$pp" | tr '[:upper:]' '[:lower:]')
#            # Check if the input is "y"
#            if [ "$pp_lowercase" = "y" ]; then
#                # Tasks to be performed if input is "y"
#                sed -i 's/\(server.*check\)/\1 send-proxy-v2/g' "$config_file"
#            fi
#        fi
#    fi
}
# Main menu
while true; do
    echo "Menu:"
    echo "1 - Install HAProxy"
    echo "2 - IP & Port Management"
    echo "3 - Health Check"     
#    echo "4 - Proxy Protocol"
    echo "5 - Exit"
    read -p "Enter your choice: " choice

    case $choice in
        1) install_haproxy;;
        2) # IP Management menu
           while true; do
               echo "IP Management Menu:"
               echo "1 - Add IP"
               echo "2 - Remove IP"
               echo "3 - Add Port"
               echo "4 - Remove Port"
               echo "5 - Back to Main Menu"
               read -p "Enter your choice: " ip_choice

               case $ip_choice in
                   1) add_ip;;
                   2) remove_ip;;
                   3) add_port;;
                   4) remove_port;;
                   5) break;;  # Return to the main menu
                   *) echo "Invalid choice. Please enter a valid option.";;
               esac
           done;;
        3) health_check;;
#        4) proxy_protocol;;
        5) echo "Exiting..."; exit;;
        *) echo "Invalid choice. Please enter a valid option.";;
    esac
done
