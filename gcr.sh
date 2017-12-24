git config user.name "sqeven"
git config user.email "admin@sqeven.com"

# clone master branch
git clone "https://${GH_TOKEN}@github.com/sqeven/gcr.git"

# get all of the gcr images
imgs=$(curl -ks 'https://console.cloud.google.com/m/gcr/entities/list'  -H 'cookie: SID=WgX93aiB6sVpD_FPLDBsPHvLnYdhtMXYt9bHsf_TmrmIvLkrnc11D84pIcS-3WB9fYIHKw.; HSID=A--M5SxveLfh2e7Jl; SSID=AqvfThGwBO94ONF2d; OSID=ZAX93cIEBWYq35v3hq6J5U3MNU3voHihnEqmrmIirWBfHluQ3Gjbb4E24vDuPoSVKpC2tg.'  -H 'content-type: application/json;charset=UTF-8'   --data-binary '["google-containers"]' | grep -P '"' | sed 's/"gcr.ListEntities"//'|cut -d '"' -f2 |sort|uniq)

# init README.md
echo -e "Google Container Registry Mirror [last sync $(date +'%Y-%m-%d %H:%M') UTC]\n-------\n\n[![Sync Status](https://travis-ci.org/sqeven/gcr.svg?branch=sync)](https://travis-ci.org/sqeven/gcr)\n\nTotal of $(echo ${imgs[@]} | grep -o ' ' | wc -l)'s gcr.io images\n-------\n\nUseage\n-------\n\n\`\`\`bash\ndocker pull gcr.io/google-containers/federation-controller-manager-arm64:v1.3.1-beta.1 \n# eq \ndocker pull sqeven/federation-controller-manager-arm64:v1.3.1-beta.1\n\`\`\`\n\n[Changelog](./CHANGES.md)\n-------\n\nImages\n-------\n\n" > gcr/README.md

# create changelog md
if [ ! -s gcr/CHANGES.md ]; then
    echo -e "\n" > gcr/CHANGES.md
fi

# sync branch tmp changelog md
if [ ! -f CHANGES.md ]; then
    touch CHANGES.md
fi

# remove all of the imgs tmp file
rm -rf gcr/google_containers/*

for img in ${imgs[@]}  ; do
    # get all  tags for this image
    gcr_content=$(curl -ks -X GET https://gcr.io/v2/google_containers/${img}/tags/list)
    
    # if this image dir not exits 
    if [ ! -d gcr/google_containers/${img} ] ; then
        mkdir -p gcr/google_containers/${img}
    fi
    
    # create image README.md
    echo -e "[gcr.io/google-containers/${img}](https://hub.docker.com/r/sqeven/${img}/tags/) \n\n----" > gcr/google_containers/${img}/README.md
    
    # create img tmp file,named by tag's name, set access's time,modify's time by this image manifest's timeUploadedMs
    echo ${gcr_content} | jq -r '.manifest[]|{k: .tag[0],v: .timeUploadedMs} | "touch -amd \"$(date -d @" + .v[0:10] +")\" gcr\/google_containers\/${img}\/"  +.k' | while read i; do
        eval $i
    done
    
    # get all of the files by last modify time after yesterday,it was new image
    new_tags=$(find ./gcr/google_containers/${img} -path "*.md" -prune -o -mtime -1 -type f -exec basename {} \;)
    
    for tag in ${new_tags[@]};do
        docker pull gcr.io/google-containers/${img}:${tag}
        
        docker tag gcr.io/google-containers/${img}:${tag} ${user_name}/${img}:${tag}
        
        docker push ${user_name}/${img}:${tag}
        
        # write this to changelogs
        echo -e "1. [gcr.io/google_containers/${img}:${tag} updated](https://hub.docker.com/r/sqeven/${img}/tags/) \n\n" >> CHANGES.md
        
        # image readme.md
        echo -e "**[gcr.io/google_containers/${img}:${tag} updated](https://hub.docker.com/r/sqeven/${img}/tags/)**\n" >> gcr/google_containers/${img}/README.md
    done

    # docker hub pull's token
    token=$(curl -ks https://auth.docker.io/token\?service\=registry.docker.io\&scope\=repository:${user_name}/${img}:pull | jq -r '.token')
    
    # get this gcr image's tags
    gcr_tags=$(echo ${gcr_content} | jq -r '.tags[]'|sort -r)
    
    # get this docker hub image's tags
    hub_tags=$(curl -ks -H "authorization: Bearer ${token}"  https://registry.hub.docker.com/v2/${user_name}/${img}/tags/list | jq -r '.tags[]'|sort -r)
    
    for tag in ${gcr_tags}
    do
        # if both of the gcr and docker hub ,not do anythings
        if [ ! -z "${hub_tags[@]}" ] && (echo "${hub_tags[@]}" | grep -w "${tag}" &>/dev/null); then 
             echo google_containers/${img}:${tag} exits
        else
            docker pull gcr.io/google-containers/${img}:${tag}
            docker tag gcr.io/google-containers/${img}:${tag} ${user_name}/${img}:${tag}
            docker push ${user_name}/${img}:${tag}
        fi
        # old img tag write to image's readme.md
        echo -e "[gcr.io/google_containers/${img}:${tag} √](https://hub.docker.com/r/sqeven/${img}/tags/)\n" >> gcr/google_containers/${img}/README.md
        
        # cleanup the docker file
        docker system prune -f -a
    done
    
    echo -e "[gcr.io/google_containers/${img} √](https://hub.docker.com/r/sqeven/${img}/tags/)\n" >> gcr/README.md
done

if [ -s CHANGES.md ]; then
    (echo -e "## $(date +%Y-%m-%d) \n" && cat CHANGES.md && cat gcr/CHANGES.md) > gcr/CHANGES1.md && mv gcr/CHANGES1.md gcr/CHANGES.md
fi

cd gcr
git add .
git commit -m "gfw gcr.io's images"
git push --quiet "https://${GH_TOKEN}@github.com/sqeven/gcr.git" master:master

exit 0