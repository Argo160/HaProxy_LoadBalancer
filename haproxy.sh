#!/bin/bash
check_haproxy_availability() {
    if command -v haproxy &>/dev/null; then
        return 0  # HAProxy is installed
    else
        return 1  # HAProxy is not installed
    fi
}
install_haproxy() {
    clear
    if check_haproxy_availability; then
        echo "HAProxy is already installed."
        echo "Press any key to return to the menu"
        read
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
            echo "Press enter to return to the menu"
            read
        else
            echo "Failed to install HAProxy."
            exit 1
        fi
    fi
}
uninstall_haproxy() {
    if check_haproxy_availability; then
        clear
        # Prompt the user for confirmation with default value 'n'
        read -p "Are you sure to uninstall the loadBalancer? (y/n) [n]: " -r answer
        # Use default value if user input is empty
        answer=${answer:-n}
        # Check the user's response
        if [[ $answer == [Yy] ]]; then
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
            # Add commands to uninstall the loadBalancer here
        else
            echo "Operation canceled. LoadBalancer will not be uninstalled."
            return
        fi
    else
        echo "HAProxy is not installed."
    fi
}
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
    clear
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
        return
    fi
    # Extract backend IP addresses from the configuration file
     backend_ips=$(grep -Eo '\b([0-9]+\.){3}[0-9]+|([0-9a-fA-F]+:){2,7}[0-9a-fA-F]+(::1)?\b' "$config_file" | sort -u)
    # Check if any backend IPs are defined
    clear
    if [ -z "$backend_ips" ]; then
        echo "No IPs defined in the configuration file yet."
    else
        echo -e "\e[1mThe current IPs defined in the configuration file:\e[0m"
        echo -e "\e[1m\e[33m$backend_ips\e[0m"
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
            front_ports=$(echo "$port" | sed 's/port//g')
            backend_name="backend$front_ports"
            echo "backend $backend_name" >> "$config_file"
            echo "    balance roundrobin" >> "$config_file"
            echo "    server server"$new_ip" $(printf "$ip_format" "$new_ip"):$front_ports check" >> "$config_file"
        done
        systemctl restart haproxy
    else
        if grep -qE "(^| )($new_ip:|\[$new_ip\]|$new_ip)( |$|\]|:)" "$config_file"; then
            echo "IP $new_ip is already present in the configuration file."
            return
        else
            # Add the new IP address to the backend sections after the line containing "balance roundrobin"
            for backend_name in $backend_names; do
                sed -i "/^\s*backend\s\+$backend_name\s*$/,/balance roundrobin/ s/\(balance roundrobin\)/\1\n    server server"$new_ip" $(printf "$ip_format" "$new_ip"):${backend_name#backend} check/" "$config_file"
             done
        fi
        echo "New IP address added to the HAProxy configuration file."
        systemctl restart haproxy
    fi
}
remove_ip() {
    config_file="/etc/haproxy/haproxy.cfg"
    backend_ips=$(grep -Eo '\b([0-9]+\.){3}[0-9]+|([0-9a-fA-F]+:){2,7}[0-9a-fA-F]+(::1)?\b' "$config_file" | sort -u)
    num_ips=$(echo "$backend_ips" | wc -l)
    # Check if any backend IPs are defined
    clear
    if [ -z "$backend_ips" ]; then
        echo "No IPs defined in the configuration file yet."
        return
    else
        echo -e "\e[1mThe current IPs defined in the configuration file:\e[0m"
        echo -e "\e[1m\e[33m$backend_ips\e[0m"
    fi
    read -p "Enter IP address to delete: " old_ip
    #check if there are more than 1 unique ip and the one is already there
    if grep -qE "(^| )($old_ip:|\[$old_ip\]|$old_ip)( |$|\]|:)" "$config_file"; then
        if [ "$num_ips" -gt 1 ]; then
            # Delete only the given IP from the backends
            sed -i "/server.*$old_ip.*check/d" "$config_file"
            echo "Deleted IP $old_ip from the backends."
            systemctl restart haproxy
        elif [ "$num_ips" -eq 1 ]; then
            # Delete the entire backend
            last_default_backend_line=$(grep -n "default_backend" "$config_file" | tail -n1 | cut -d: -f1)
            sed -i "${last_default_backend_line}q" "$config_file"
            #sed -i "${last_default_backend_line},$ d" "$config_file"
            echo "Deleted the entire backend where IP $old_ip was the only one."
            systemctl restart haproxy
        fi
    else
        echo "IP $old_ip is not present in the configuration file."
    fi
}
add_port() {
    clear
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
        read -p "Enter the port to add: " port_to_add
        # Create the configuration snippet
        config_snippet="frontend port${port_to_add}
        bind *:${port_to_add}
        default_backend backend${port_to_add}"
        # Append the snippet to the end of the file
        echo "$config_snippet" >> "$config_file"
        echo "Successfully added the configuration snippet for port ${port_to_add}."
    else
        echo -e "\e[1mCurrent Ports::\e[0m"
        echo -e "\e[33m$frontend_ports\e[0m"
        read -p "Enter the port to add: " port_to_add
        if [ -n "$(grep -E "frontend port${port_to_add}\\b" "$config_file")" ]; then
                echo "The Port is already available"
                return
        fi
        # Find the last line containing "default_backend"
        last_default_backend_line=$(grep -n "default_backend" "$config_file" | tail -n1 | cut -d: -f1)
        # Append the new frontend configuration after the last line containing "default_backend"
        new_frontend_config="frontend port${port_to_add}\\
    bind *:${port_to_add}\\
    default_backend backend${port_to_add}"
        sed -i "${last_default_backend_line} a\\
${new_frontend_config}" "$config_file"
        echo "Successfully added the new frontend configuration for port ${port_to_add}."
        # Extract backend IP addresses from the configuration file
        backend_ips=$(grep -Eo '\b([0-9]+\.){3}[0-9]+|([0-9a-fA-F]+:){2,7}[0-9a-fA-F]+(::1)?\b' "$config_file" | sort -u)

        # Check if any backend IPs are defined
        clear
        if [ -z "$backend_ips" ]; then
                echo "No IPs defined in the configuration file yet."
        else
                echo "backend backend$port_to_add" >> "$config_file"
                echo "    balance roundrobin" >> "$config_file"
                for ip in $backend_ips; do
                        # Check if the entered IP address is valid
                        if [[ $ip =~ ^[0-9.]+$ ]]; then
                                # IPv4 address
                                ip_format="%s"
                        elif [[ $ip =~ ^[0-9a-fA-F:.]+$ ]]; then
                                # IPv6 address
                                ip_format="[%s]"
                        fi
                        echo "    server server"$ip" $(printf "$ip_format" "$ip"):$port_to_add check" >> "$config_file"
                done
                systemctl restart haproxy
                echo -e "\e[1mThe current IPs defined in the configuration file:\e[0m"
                echo -e "\e[1m\e[33m$backend_ips\e[0m"
        fi
    fi
}
remove_port() {
    clear
    config_file="/etc/haproxy/haproxy.cfg"
    # Extract frontend port numbers from the configuration file
    frontend_ports=$(grep -E "^\s*frontend\s+port[0-9]+" "$config_file" | awk '{print $2}')
    # Check if any frontend ports are defined
    if [ -z "$frontend_ports" ]; then
        echo "No ports defined to delete"
        return
    else
        echo -e "\e[1mCurrent Ports::\e[0m"
        echo -e "\e[33m$frontend_ports\e[0m"
        read -p "Enter the port to delete: " port_to_delete
        existing_frontend=$(grep -E "frontend port${port_to_delete}\\b" "$config_file")
        if [ -n "$existing_frontend" ]; then
            # Delete the frontend configuration for the given port
            sed -i "/^frontend port${port_to_delete}/,+2 d" "$config_file"
            sed -i "/^backend backend${port_to_delete}$/,/^backend/ {/^backend backend${port_to_delete}$/b; /^backend/!d}" "$config_file"
            sed -i "/^backend backend${port_to_delete}$/d" "$config_file"
            echo "Successfully deleted for port ${port_to_delete}."
            systemctl restart haproxy
        else
            echo "Frontend configuration for port ${port_to_delete} does not exist."
        fi
    fi
}
health_check() {
    clear
    config_file="/etc/haproxy/haproxy.cfg"
    # Extract backend names from the configuration file
    backend_names=$(awk '/^\s*backend\s+/{print $2}' "$config_file")
    for backend_name in $backend_names; do
        server_info=$(echo "show stat" | socat stdio /run/haproxy/admin.sock | awk -F',' "/^$backend_name,/ && !/BACKEND/{print \$74,\$18}")
        echo "$server_info" | while read -r server_ip status; do
            if [[ "$status" == "UP" ]]; then
                echo -e "\e[32mServer at $server_ip is up.\e[0m"  # Green color for UP
            else
                echo -e "\e[31mServer at $server_ip is down.\e[0m"  # Red color for DOWN
            fi
        done
    done
    echo "Press Enter to return to main Menu"    
    read
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
create_backup() {
    config_file="/etc/haproxy/haproxy.cfg"
    backup_file="/etc/haproxy/haproxy.cfg.back"
    clear
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.back
    echo -e "\e[32mBackup Successfuly created\e[0m"
}
restore_backup() {
    config_file="/etc/haproxy/haproxy.cfg"
    backup_file="/etc/haproxy/haproxy.cfg.back"
    clear
    cp /etc/haproxy/haproxy.cfg.back /etc/haproxy/haproxy.cfg
    systemctl restart haproxy
    echo -e "\e[32mBackup Successfuly Restored\e[0m"
}
Reset_Config() {
        clear
        # Download the haproxy.cfg from GitHub and overwrite the original file
        wget -O /etc/haproxy/haproxy.cfg https://raw.githubusercontent.com/Argo160/HaProxy_LoadBalancer/main/haproxy.cfg
        echo -e "\e[32mThe Setting Restored to default\e[0m"
        echo "You need to specify ports and ip addresses"
}
balance_algo() {
    clear
    config_file="/etc/haproxy/haproxy.cfg"
    backend_names=$(awk '/^\s*backend\s+/{print $2}' "$config_file")
    # Function to extract the balance algorithm for a given backend
    get_balance_algorithm() {
         local backend_name="$1"
    grep -A 2 -E "backend $backend_name$" "$config_file" | grep -oE "balance\s+\w+" | awk '{print $2}'
    }
    # Function to check if the balance algorithm is roundrobin
    is_roundrobin() {
        local algorithm="$1"
    [[ "$algorithm" == "roundrobin" ]]
    }
    # Function to check if the balance algorithm is leastconn
    is_leastconn() {
        local algorithm="$1"
        [[ "$algorithm" == "leastconn" ]]
    }
    # Main script
    first_backend=$(grep -m 1 -E "^backend " "$config_file" | awk '{print $2}')
    balance_algorithm=$(get_balance_algorithm "$first_backend")
    if is_roundrobin "$balance_algorithm"; then
        echo -e "\e[32mCurrent Balance Algorithm is: ROUNDROBIN\e[0m"
        read -p "Do you want to change it to Leastconn? (y/n): " pp
        # Convert input to lowercase
        pp_lowercase=$(echo "$pp" | tr '[:upper:]' '[:lower:]')
        # Check if the input is "y"
        if [ "$pp_lowercase" = "y" ]; then
            # Tasks to be performed if input is "y"
            for backend_name in $backend_names; do
                sed -i "/^backend $backend_name$/,/^$/ s/^    balance .*/    balance leastconn/" "$config_file"
            done
            systemctl restart haproxy
            echo -e "\e[32mChanged successfuly\e[0m"
            read -n 1 -s -r -p "Press any key to continue"
            echo
        fi
    elif is_leastconn "$balance_algorithm"; then
        echo -e "\e[32mCurrent Balance Algorithm is: LEASTCONN\e[0m"
        read -p "Do you want to change it to Roundrobin? (y/n): " pp
        # Convert input to lowercase
        pp_lowercase=$(echo "$pp" | tr '[:upper:]' '[:lower:]')
        # Check if the input is "y"
        if [ "$pp_lowercase" = "y" ]; then
            for backend_name in $backend_names; do
                sed -i "/^backend $backend_name$/,/^$/ s/^    balance .*/    balance roundrobin/" "$config_file"
            done
            systemctl restart haproxy
            echo -e "\e[32mChanged successfuly\e[0m"
            read -n 1 -s -r -p "Press any key to continue"
            echo
        fi
    else
        echo "No Balance Algorithm Found"
    fi
}
# Main menu
while true; do
clear
    echo "Menu:"
    echo "1 - Install HAProxy"
    echo "2 - IP & Port Management"
    echo "3 - Health Check"
    echo "4 - Proxy Protocol"
    echo "5 - Balance Algorithm"
    echo "6 - Backup"
    echo "7 - Reset Config"
    echo "8 - Uninstall"
    echo "0 - Exit"
    read -p "Enter your choice: " choice
    case $choice in
        1) install_haproxy;;
        2) # IP Management menu
           while true; do
               echo "    IP Management Menu:"
               echo "    1 - Add IP"
               echo "    2 - Remove IP"
               echo "    3 - Add Port"
               echo "    4 - Remove Port"
               echo "    9 - Back to Main Menu"
               read -p "Enter your choice: " ip_choice
               case $ip_choice in
                   1) add_ip;;
                   2) remove_ip;;
                   3) add_port;;
                   4) remove_port;;
                   9) break;;  # Return to the main menu
                   *) echo "Invalid choice. Please enter a valid option.";;
               esac
           done;;
        3) health_check;;
        4) proxy_protocol;;
        5) balance_algo;;
        6) # Backup
           while true; do
               echo "    Backup Management Menu:"
               echo "    1 - Create Backup"
               echo "    2 - Restore Backup"
               echo "    9 - Back to Main Menu"
               read -p "Enter your choice: " backup_choice
               case $backup_choice in
                   1) create_backup;;
                   2) restore_backup;;
                   9) break;;
                   *) echo "Invalid choice. Please enter a valid option.";;
               esac
           done;;
        7) Reset_Config;;
        8) uninstall_haproxy;;
        0) echo "Exiting..."; exit;;
        *) echo "Invalid choice. Please enter a valid option.";;
    esac
done
