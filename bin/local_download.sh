BUILD_NUM=$1
echo downloading build ${BUILD_NUM}

mkdir maguro-sensorlog-dev-${BUILD_NUM}
cd maguro-sensorlog-dev-${BUILD_NUM}
scp nesl@128.97.93.158:/aosp/jenkins_home/jobs/jenkins-jb-privacy/workspace/copy/jenkins-jb-privacy-github_jb-privacy-sensorlog-dev-${BUILD_NUM}/out/target/product/maguro/android-info.txt ./ 
scp nesl@128.97.93.158:/aosp/jenkins_home/jobs/jenkins-jb-privacy/workspace/copy/jenkins-jb-privacy-github_jb-privacy-sensorlog-dev-${BUILD_NUM}/out/target/product/maguro/*.img ./ 

export ANDROID_PRODUCT_OUT=$PWD

echo finished.
