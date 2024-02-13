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
    # Check if the configuration file exists
    if [ ! -f "$config_file" ]; then
        echo "Error: HAProxy configuration file not found: $config_file"
        exit 1
    fi
    # Extract frontend port numbers from the configuration file
    frontend_ports=$(grep -E "^\s*frontend\s+port[0-9]+" "$config_file" | awk '{print $2}')
    # Check if any frontend ports are defined
    if [ -z "$frontend_ports" ]; then
        echo "Please specify at least one port in the HAProxy configuration file before adding IP addresses."
    else
        echo "Frontend ports defined in the configuration file:"
        echo "$frontend_ports"
        read
    fi

    # Extract backend IP addresses from the configuration file
    backend_ips=$(grep -Eo '\b([0-9]+\.){3}[0-9]+|([0-9a-fA-F]+:){2,7}[0-9a-fA-F]+\b' "$config_file" | sort -u)

    # Check if any backend IPs are defined
    clear
    if [ -z "$backend_ips" ]; then
        echo "No IPs defined in the configuration file yet."else
        echo -e "\e[1mThe current IPs defined in the configuration file:\e[0m"
        echo "$backend_ips"
    fi

    # Prompt the user for the new IP address
    read -p "Enter the new IP address: " new_ip

    # Check if the entered IP address is valid
    if [[ $new_ip =~ ^[0-9.]+$ ]]; then
        # IPv4 address
        ip_format="%s"
    elif [[ $new_ip =~ ^[0-9a-fA-F:.]+$ ]]; then
        # IPv6 address
        ip_format="[%s]"
    else
        echo "Error: Invalid IP address format."
        exit 1
    fi

    # Extract backend names from the configuration file
    backend_names=$(awk '/^\s*backend\s+/{print $2}' "$config_file")

    #check if backend is empty or not
    if [ -z "$backend_names" ]; then
        for port in $frontend_ports; do
            backend_name="backend$port"
            echo "backend $backend_name" >> "$config_file"
            echo "    balance roundrobin" >> "$config_file"
            echo "    server server1 $ip_format:$port check" >> "$config_file"
        done
    else
        # Add the new IP address to the backend sections after the line containing "balance roundrobin"
        for backend_name in $backend_names; do
            echo "Adding $new_ip to backend $backend_name"
            sed -i "/^\s*backend\s\+$backend_name\s*$/,/balance roundrobin/ s/\(balance roundrobin\)/\1\n    server server1 $(printf "$ip_format" "$new_ip"):${backend_name#backend} check/" "$config_file"
        done
    fi
    echo "New IP address added to the HAProxy configuration file."
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
            systemctl restart haproxy
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
    if ! grep -qE '^\s*server ' "$config_file"; then
        echo "Atleast one ip address is required in configuration file"
    else
        if grep -qE '^\s*server .* check send-proxy-v2$' "$config_file"; then
            echo -e "\e[32mProxy Protocol is Enabled.\e[0m"  # Green color for Enabled
            read -p "Do you want to Disable it? (y/n): " pp
            # Convert input to lowercase
            pp_lowercase=$(echo "$pp" | tr '[:upper:]' '[:lower:]')
            # Check if the input is "y"
            if [ "$pp_lowercase" = "y" ]; then
                # Tasks to be performed if input is "y"
                sed -i 's/send-proxy-v2//g' "$config_file"
                systemctl restart haproxy
            fi
        else
            echo -e "\e[33mProxy Protocol is Disabled.\e[0m"
            read -p "Do you want to Enable it? (y/n): " pp    
            # Convert input to lowercase
            pp_lowercase=$(echo "$pp" | tr '[:upper:]' '[:lower:]')
            # Check if the input is "y"
            if [ "$pp_lowercase" = "y" ]; then
                # Tasks to be performed if input is "y"
                sed -i 's/\(server.*check\)/\1 send-proxy-v2/g' "$config_file"
                systemctl restart haproxy
            fi
        fi
    fi
}
# Main menu
while true; do
    echo "Menu:"
    echo "1 - Install HAProxy"
    echo "2 - IP & Port Management"
    echo "3 - Health Check"     
    echo "4 - Proxy Protocol"
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
        4) proxy_protocol;;
        5) echo "Exiting..."; exit;;
        *) echo "Invalid choice. Please enter a valid option.";;
    esac
done
