#!/bin/env bash
echo "Pulling certificate for ${FQDN}"

## SSL CERTIFICATES
if [[ -v $FQDN ]]; then
    echo "FQDN is not set"
    exit 1
elif [[ -z "$FQDN" ]]; then
    echo "FQDN is set to the empty string"
    exit 1
fi

secret_re='.*"SecretString": "(.*)",.*'
cert_re='.*"CertificateChain": "(.*-----).*"PrivateKey": "(.*-----).*'


cert_arn=$(eval "aws acm list-certificates --query 'CertificateSummaryList[?DomainName==\`${FQDN}\`]'.[CertificateArn] --output text")

if [[ $(aws secretsmanager get-secret-value --secret-id ${FQDN}) =~ $secret_re ]]; then
  cert_pass_phrase=${BASH_REMATCH[1]}
  echo "$secret_re"
  echo $cert_pass_phrase
else
  echo "No cert pass phrase by the domain ${FQDN}"
  exit 1
fi

if [[ $(aws acm export-certificate --certificate-arn $cert_arn --passphrase $cert_pass_phrase) =~ $cert_re ]]; then

  if [ ! -d "/etc/ssl/certs/" ]; then
    mkdir "/etc/ssl/certs/"
    if [ ! -f "/etc/ssl/certs/${FQDN}.crt"]; then
      echo "Creating key file for certificate key"
    fi
  fi
  if [[ "$(echo ${BASH_REMATCH[1]})"!="$(cat /etc/ssl/certs/${FQDN}.crt)" ]]; then
    touch "/etc/ssl/certs/${FQDN}.crt"
    echo "${BASH_REMATCH[1]}" > "/etc/ssl/certs/${FQDN}.crt"
    echo "copying to crt file /etc/ssl/certs/${FQDN}.crt"
    restart_nginx="true"
  else
  	echo "Certificate value has not changed, not updating."
  fi

  if [ ! -d "/etc/ssl/private/" ]; then
    mkdir "/etc/ssl/private/"
    if [ ! -f "/etc/ssl/private/${FQDN}.key"]; then
      echo "Creating key file for certificate key"
    fi
  fi
  if [[ "$(echo ${BASH_REMATCH[2]})"!="$(cat /etc/ssl/private/${FQDN}.key)" ]]; then
    touch "/etc/ssl/private/${FQDN}.key"
    echo "${BASH_REMATCH[2]}" > "/etc/ssl/private/${FQDN}.key"
    echo "Copying SSL key to key file /etc/ssl/private/${FQDN}.key"
    restart_nginx="true"
  else
    echo "Key value has not changed, not updating."
  fi

fi

### NGINX
# Restore original default config if no config has been provided
if [[ ! "$(ls -A /etc/nginx/conf.d)" ]]; then
    cp -a /etc/nginx/.conf.d.orig/. /etc/nginx/conf.d 2>/dev/null
fi

# Replace variables $ENV{<environment varname>}
function ReplaceEnvironmentVariable() {
    grep -rl "\$ENV{\"$1\"}" $3|xargs -r \
        sed -i "s|\\\$ENV{\"$1\"}|$2|g"
}

if [ -n "$DEBUG" ]; then
    echo "Environment variables:"
    env
    echo "..."
fi

# Replace all variables
for _curVar in `env | awk -F = '{print $1}'`;do
    # awk has split them by the equals sign
    # Pass the name and value to our function
    ReplaceEnvironmentVariable ${_curVar} ${!_curVar} /etc/nginx/conf.d/*
done

# Run nginx
service nginx start

if [ $restart_nginx=="true" ]; then
  echo "restarting nginx per certificate change"
  service nginx stop
  service nginx start
fi
