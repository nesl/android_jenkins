export init_tag='android-4.2.2_r1'
export dev_refspec='github/jb-privacy'
export local_manifest='
<manifest>
  <remote name="github" fetch="https://github.com" />
  <remove-project name="platform/frameworks/native" />
  <project path="frameworks/native" remote="github" name="nesl/platform_frameworks_native" revision="refs/tags/android-4.2.2_r1" />
  <remove-project name="platform/frameworks/base" />
  <project path="frameworks/base" remote="github" name="nesl/platform_frameworks_base" revision="refs/tags/android-4.2.2_r1" />
</manifest>
'
export dev_projects='frameworks/base frameworks/native'
export lunch='full_mako-eng'

FLAG_NO_SYNC=false
FLAG_NO_CLOBBER=false
FLAG_UPDATE_API=false
FLAG_copy_out=false
FLAG_use_mirror=false

JOB_NAME=android
WORKSPACE=/aosp/jenkins_home/jobs/local_test/workspace/
BUILD_NUMBER=5

mkdir -p $WORKSPACE

. jenkins_make_android.sh
