#!/bin/bash
TEMPLATES=(
  "go"
  "java"
  "javascript"
  "javascript-cdn"
  "openfeature-javascript"
  "nextjs-app-router"
  "nodejs"
  "nodejs-typescript"
  "openfeature-nodejs-typescript"
  "php"
  "php-codeigniter"
  "php-laravel"
  "php-leaf"
  "php-slim"
  "php-symfony"
  "python"
  "react-typescript"
  "openfeature-react-typescript"
  "react-with-provider"
  "ruby"
  "vue3"
)

#####################################
# Utils for printing colored text
#####################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
LIGHT_PURPLE='\033[1;35m'
NC='\033[0m' # No Color

echo_color() {
  echo -e "${1}${@:2}${NC}"
}

#####################################
# Parse and validate parameters
#####################################
while getopts ":o:t:k:" option; do
  case $option in
    o)
      OUTPUT_DIR="$OPTARG"
      ;;
    t)
      TEMPLATE_KEY="$OPTARG"
      ;;
    k)
      SDK_KEY="$OPTARG"
      ;;
  esac
done

if [[ -z $OUTPUT_DIR ]]
then
    echo_color $LIGHT_PURPLE "Please specify an output path:"
    read OUTPUT_DIR
    if [[ -z $OUTPUT_DIR ]]
    then
        echo_color $YELLOW "No output path specified. Exiting..."
        exit 1
    fi
fi

if [[ -z $TEMPLATE_KEY || ! ${TEMPLATES[@]} =~ $TEMPLATE_KEY ]]
then
    echo_color $LIGHT_PURPLE "Select a template:"
    select key in "${TEMPLATES[@]}"; do
      TEMPLATE_KEY="$key"
      break
    done
fi

if [[ -z $SDK_KEY ]]
then
    echo_color $LIGHT_PURPLE "Enter your SDK key:"
    read SDK_KEY
    if [[ -z $SDK_KEY ]]
    then
        echo_color $YELLOW "No SDK key specified. Exiting..."
        exit 1
    fi
fi

#####################################
# Fetch source code from GitHub repository
#####################################

echo_color $BLUE 'Fetching source code'

BRANCH="main"
repo_url="https://github.com/DevCycleHQ-Labs/example-$TEMPLATE_KEY/archive/refs/heads/$BRANCH.zip"
folder_name="example-$TEMPLATE_KEY-$BRANCH"
target_zip="$BRANCH.zip"

# Download the zipped contents of the repository
curl "$repo_url" --location --output $target_zip &> /dev/null

# Unzip the downloaded file
unzip $target_zip &> /dev/null
mv $folder_name $OUTPUT_DIR

# Remove the downloaded zip file
rm $target_zip

# Change directory to the output directory
cd $OUTPUT_DIR

#####################################
# Setup env file
#####################################

echo_color $BLUE 'Generating .env file'

# Rename .env.sample to .env
mv .env.sample .env

# Replace <YOUR_SDK_KEY> in the .env file with the SDK key
sed -i~ "s/<YOUR_SDK_KEY>/$SDK_KEY/g" ".env"
rm .env~

#####################################
# Install dependencies and validate requirements
#####################################

echo_color $BLUE 'Installing dependencies'

check_for_command() {
  if ! command -v $1 &> /dev/null
  then
    echo_color $YELLOW "'$1' could not be found in PATH. Exiting..."
    exit 1
  fi
}

#### Python ####
if [ "$TEMPLATE_KEY" = "python" ]; then
  check_for_command "python3"
  install_command="python3 -m pip install --user -r requirements.txt && python3 manage.py migrate"
#### Go ####
elif [ "$TEMPLATE_KEY" = "go" ]; then
  check_for_command "go"
  install_command="go mod download"
#### Java ####
elif [ "$TEMPLATE_KEY" = "java" ]; then
  if type -p java > /dev/null; then
    _java=java
  elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    _java="$JAVA_HOME/bin/java"
  else
    echo_color $YELLOW "Java could not be found in PATH. Exiting..."
    exit 1
  fi

  required_version="17"
  # Parse java version from output
  version="$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')"
  # Get major version
  version="${version%%.*}"
  if [[ $version -lt $required_version ]]; then
    echo_color $YELLOW "Java version must be >= $required_version, found $version. Exiting..."
    exit 1
  fi
  skip_install=true
#### PHP Frameworks ####
elif [[ "$TEMPLATE_KEY" == "php" || "$TEMPLATE_KEY" =~ php-.* ]]; then
  check_for_command "php"

  if type -p composer > /dev/null; then
    _composer=composer
  else
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php
    php -r "unlink('composer-setup.php');"
    _composer="php composer.phar"
  fi

  install_command="$_composer install"

#### Ruby ####
elif [ "$TEMPLATE_KEY" = "ruby" ]; then
  check_for_command "docker"
  skip_install=true

#### JavaScript ####
else
  check_for_command "npm"
  install_command="npm install"
fi

if [ $skip_install ] || eval "$install_command"; then
  echo -e "\n${GREEN}Success!${NC} Project created in $OUTPUT_DIR\n"
else
  echo_color $YELLOW "Failed to install dependencies. See the README for setup instruction. Exiting..."
  exit 1
fi

#####################################
# Start dev server & log dev instructions
#####################################

# Parse dev instructions from README.md
# - Get lines between ### Development and ##
# - Remove lines starting with ### or ##
dev_instructions=$(sed -n '/### Development/,/##/p' README.md | sed '/^##/d')

if [[ -z $dev_instructions ]]
then
    echo_color $YELLOW 'Unable to parse development instructions'
    exit 1
fi

# Get command within backticks
dev_command=$(echo "$dev_instructions" | sed -n '/`/,/`/p' | head -n 1 | sed 's/`//g')

echo -e "${BLUE}Starting development server${NC}"

print_dev_instructions() {
  echo -e "\n----------------------------------------"
  echo -e "How to run the development server: \n"
  echo_color $BLUE "cd $OUTPUT_DIR"

  # Replace command with colored command
  echo -e "${dev_instructions/"\`$dev_command\`"/$BLUE$dev_command$NC}"
}

# Log dev instructions on exit
trap 'print_dev_instructions' INT

# Open browser if necessary
if [ "$TEMPLATE_KEY" == "python" ] || [ "$TEMPLATE_KEY" == "go" ] || [ "$TEMPLATE_KEY" == "ruby" ]; then
  PORT=8000
elif [[ "$TEMPLATE_KEY" == "java" ]] || [[ "$TEMPLATE_KEY" == "php" ]] || [[ "$TEMPLATE_KEY" == php-* ]]; then
  PORT=8080
fi

if [ -n "$PORT" ]; then
  open "http://localhost:$PORT"
fi

# Start dev server
eval "$dev_command"

