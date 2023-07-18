#!/bin/bash

clearConfig=$1

homeDir=/opt/vbms
scriptsDir=${homeDir}/Delivery
configDir=${homeDir}/config
gitRepoName=vbms-protection-grid
gitRepoDir=${homeDir}/${gitRepoName}

env=$(hostname | cut -d'-' -f 2)
env=${env,,}
project=$(hostname | cut -d'-' -f 1)
project=${project,,}

if [[ ${env} == "alt" || ${env} == "dev" || ${env} == "tst" ]]; then
  cluster="dev"
else
  cluster="stage"
fi

if [[ ${project} == "vbr" ]]; then
  projectConfig=vbmsr
  projectName=rating
elif [[ ${project} == "vba" ]]; then
  projectConfig=vbmsa
  projectName=awards
elif [[ ${project} == "vbc" ]]; then
  projectConfig=vbmsc
  projectName=correspondence
elif [[ ${project} == "vb" ]]; then
  projectConfig=vbms
  projectName=core
else
  echo "Error: Unrecognized project type!"
fi

cd ${gitRepoDir} ; git fetch --all ; git reset --hard origin/master ; cd -

ln -sfn ${gitRepoDir} ${homeDir}/${projectConfig}-protection-grid ; \
ln -sfn ${gitRepoDir}/vbms-configuration ${gitRepoDir}/${projectConfig}-configuration ; \
ln -sfn ${gitRepoDir}/vbms-configuration/${env} ${configDir} ; \
ln -sfn ${configDir}/domain-${projectName}.xml ${configDir}/domain.xml

if [[ ${project} == "vb" ]]; then
  if [[ -f ${scriptsDir}/translate_domain_props.py ]]; then #17.0+
    python ${scriptsDir}/translate_domain_props.py core
    source ${configDir}/domain.properties > /dev/null 2>&1
    hosts=($(echo ${machines} | sed 's/,/ /g'))
  else #16.1
    python ${gitRepoDir}/${projectConfig}-domain/12c/translate_deploy_props.py
    source ${configDir}/deploy.prop
    hosts=($(echo ${SRV_IP} | sed 's/,/ /g'))
  fi
elif [[ -f ${gitRepoDir}/${projectConfig}-domain/12c/translate_deploy_props.py ]]; then
  python ${gitRepoDir}/${projectConfig}-domain/12c/translate_deploy_props.py
  source ${configDir}/deploy.prop
  hosts=($(echo ${MACHINES} | sed 's/,/ /g'))
  if [[ ${hosts} == "" ]]; then
    hosts=($(echo ${SRV_IP} | sed 's/,/ /g'))
  fi
fi

sLen=${#hosts[@]}
for (( i=0; i<${sLen}; i++ ));
do
    host=${hosts[$i]}
    echo "##########################################"
    echo "Syncing configuration on ${host}:${configDir}"
    echo "##########################################"

    if [[ "${clearConfig}" == "-d" ]] ; then
        ssh -q ${host} "rm -rf ${configDir}/* ; rm -rf ${configDir}"
    fi

    ssh -q ${host} \
      "cd ${gitRepoDir} ; \
       git fetch --all ; \
       git reset --hard origin/master ; \
       chmod -R 750 ${gitRepoDir} ; \
       chmod 755 ${gitRepoDir} ; \
       chmod -R 755 ${gitRepoDir}/vbms-configuration"

    ssh -q ${host} \
      "ln -sfn ${gitRepoDir} ${homeDir}/${projectConfig}-protection-grid ; \
       ln -sfn ${gitRepoDir}/vbms-configuration ${gitRepoDir}/${projectConfig}-configuration ; \
       ln -sfn ${gitRepoDir}/vbms-configuration/${env} ${configDir} ; \
       ln -sfn ${configDir}/domain-${projectName}.xml ${configDir}/domain.xml"

    bootstrapEnv=${env}
    if [[ ${env} == "ivv" ]]; then
      bootstrapEnv="sqa"
    fi
    GIT_TOKEN=$(aws secretsmanager get-secret-value --secret-id dev/VBMS/git-token 2>/dev/null | jq -r .SecretString | jq -r .token)
    ssh -q ${host} \
      "sed -i 's/{GIT_TOKEN}/${GIT_TOKEN}/g' /opt/vbms/config/bootstrap-${bootstrapEnv}.yml"
      
    if [[ ${project} != "vb" ]]; then
        ssh -q ${host} \
          "python ${gitRepoDir}/${projectConfig}-domain/12c/translate_deploy_props.py"
    fi
done

WL_TOKEN=$(aws secretsmanager get-secret-value --secret-id "${cluster}"/VBMS/wl-token 2>/dev/null | jq -r .SecretString | jq -r .token)
sed -i "s/{WL_TOKEN}/${WL_TOKEN}/g" /opt/vbms/config/domain*.xml

echo "Done!"

exit 0
