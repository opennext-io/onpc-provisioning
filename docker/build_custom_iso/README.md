# Docker container for building custom images

# Building the container
tag=custombuild:latest
docker build -t $tag .

# Running it with proper parameters (here proxy) and using volume for resulting ISO to be stored on host
# Note that dir should NOT be set to /root due to called script location defined in Dockerfile
dir=/tmp
docker run -t -e 'opts=-p http://192.168.0.116:8080/ ' -e "iso=$dir/custom.iso" -v $(pwd):$dir $tag

# Asking for command line usage
docker run -t -e 'opts=-h' $tag
