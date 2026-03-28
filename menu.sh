#!/usr/bin/env bash                                                                                               
                                                                                                                    
# --- Menu Test ---                                                                                               
                                                                                                                    
MENUCHOICES=(                                                                                                     
    "docker:Docker Engine (amd64)" "ON"                                                                             
    "vscode:Visual Studio Code" "ON"                                                                                
    "tailscale:Tailscale VPN" "ON"                                                                                  
    "brave:Brave Browser" "OFF"                                                                                     
    "ollama:Ollama (Local LLM Runner)" "ON"                                                                         
    "lmstudio:LM Studio" "OFF"                                                                                      
    "openclaw:OpenClaw Quickstart" "OFF"                                                                            
)                                                                                                                 
                                                                                                                    
show_menu() {                                                                                                     
    local choices=("$@")                                                                                          
    local selection=""                                                                                            
    for choice in "${choices[@]}"; do                                                                             
        IFS=":" read -r label value <<< "$choice"                                                                 
        echo "[$value] $label"                                                                                    
    done                                                                                                          
                                                                                                                    
    while true; do                                                                                                
        CHOICES=$(dialog --menu "Select programs to install" 20 78 10 "${selection}" "${MENUCHOICES[@]}")         
        RET=$?                                                                                                    
        if [[ $RET -eq 0 ]]; then                                                                                 
            # Save selections to state                                                                            
            local cleaned                                                                                         
            for choice in "${choices[@]}"; do                                                                     
                IFS=":" read -r label value <<< "$choice"                                                         
                if [ "$value" = "ON" ]; then                                                                      
                    selection+="$label "                                                                          
                fi                                                                                                
            done                                                                                                  
            echo "$selection" > /tmp/selection.txt                                                                
            break                                                                                                 
        elif [[ $RET -eq 1 || $RET -eq 255 ]]; then                                                               
            # Cancel or ESC pressed - exit onboarding                                                             
            tty_print "Exiting onboarding."                                                                       
            exit 0                                                                                                
        fi                                                                                                        
    done                                                                                                          
}                                                                                                                 
                                                                                                                    
show_menu "${MENUCHOICES[@]}"      