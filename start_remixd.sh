#!bin/bash/
echo "checking the latest version..."

if [ -z ${1+x} ]; then
  echo "Forgot to add the <DIRECTORY>? try again";
  echo "Usage: $0 <DIRECTORY_NAME>";
fi

current_ver=$(npm show @remix-project/remixd version)
installed_ver=$(pnpm list -g @remix-project/remixd | grep "remix" | awk -F" " '{print $NF}')

echo "Latest version: ${current_ver}"
echo "Installed version: ${installed_ver}"

if [[ "$current_ver" == "$installed_ver" ]]; then
  remixd -s $1 -u https://remix.ethereum.org;
else   
  echo "Versions don't match, update it."
  echo "pnpm update -g @remix-project/remixd"
fi
