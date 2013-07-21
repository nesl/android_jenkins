#!/bin/bash
# Author: Kasturi Raghavan (kastur@gmail.com)

# Required args:
# (Usually provided by jenkin) JOB_NAME, BRANCH_JOB, BUILD_NUMBER
# init_tag
# dev_refspec
# local_manifest
# dev_projects
# lunch

set +x

DONE_ASCII='
---------------------------------
  ____     ___    _   _   _____ 
 |  _ \   / _ \  | \ | | | ____|
 | | | | | | | | |  \| | |  _|  
 | |_| | | |_| | | |\  | | |___ 
 |____/   \___/  |_| \_| |_____|
---------------------------------
'

FAIL_ASCII='
---------------------------------
  _____      _      ___   _     
 |  ___|    / \    |_ _| | |    
 | |_      / _ \    | |  | |    
 |  _|    / ___ \   | |  | |___ 
 |_|     /_/   \_\ |___| |_____|
---------------------------------
'

trap "echo \"${FAIL_ASCII}\"" EXIT

function verbose() {
  (set -v; exec $@)
}

set -e
echo "Setting up variables"
export LANG='en_US.UTF-8'  # The default ASCII encoding causes javac errors.
export USE_CCACHE=1
export CCACHE_DIR=/scratch/aosp/ccache

PUBLIC_FQDN=android.0x72.com
JOB_URL=http://${PUBLIC_FQDN}:8080/job/${JOB_NAME}/
REPO=/aosp/bin/repo
#ANNOTATE="annotate-output +%Y-%m-%d-%H:%M:%S.%N"
ANNOTATE= # Disabled for now.
FLOCK=/aosp/bin/flock
VERBOSE=verbose

if [ FLAGS_use_mirror == "true" && -d /aosp/mirror ]; then
  INIT_URL=/aosp/mirror
else
  INIT_URL=https://android.googlesource.com/platform/manifest
fi

# Replace "/" since we don't want to create nested directories.
BRANCH_JOB="${JOB_NAME}-${dev_refspec////_}"
BRANCH_JOB_NUMBERED=${BRANCH_JOB}-${BUILD_NUMBER}
LOG_DIR=$WORKSPACE/logs/${BRANCH_JOB_NUMBERED}
BUILD_DIR=/scratch/aosp/android  # Used to be based on BRANCH_JOB, but no longer.
LOCK_FILE=${BUILD_DIR}/LOCK
OUT_COPY_DIR=$WORKSPACE/copy/${BRANCH_JOB_NUMBERED}
SDK_COPY_DIR=$WORKSPACE/copy/${BRANCH_JOB_NUMBERED}

# The LOG_DIR should be unique (i.e. build numbered), but clean to be sure.
set -v
mkdir -p ${BUILD_DIR} 
cd ${BUILD_DIR}

rm -rf ${LOG_DIR} 
mkdir -p ${LOG_DIR}

# Acquire lock to prevent two builds on same BUILD_DIR
# Make sure to unlock on exit via trap.
touch ${LOCK_FILE}
trap "$FLOCK --unlock ${LOCK_FILE} && echo \"${FAIL_ASCII}\"" EXIT
echo "Waiting for lock."
$FLOCK --exclusive ${LOCK_FILE}
echo "Acquired exclusive lock."

# Put a symbolic link to the build directory in jenkins workspace.
rm -f $WORKSPACE/build_directory
ln -s ${BUILD_DIR} $WORKSPACE/build_directory
set +v

function print_log_url() {
  echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  for log in $@; do
  echo STREAMING LOGS $log ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/$log/'*view*'
  done;
  echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
}

echo "Environment after setup. $(get_log_url SETUP_ENV)"
(env; java -version) >${LOG_DIR}/SETUP_ENV 2>&1

# For convenience, print urls of log files.
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
echo SYSTEM DASHBOARD : http://${PUBLIC_FQDN}:8000/cgi/dash
echo STREAMING LOGS TO: ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

print_log_url SYNC sync_init sync_aosp sync_override.xml sync_github \
    sync_checkout sync_drivers sync_status
(
set -v
if [ ${FLAG_NO_SYNC} != "true" ]; then 

  # Remove .repo/local_manifest.xml and .repo/local_manifests directory.
  rm -rf .repo/local_manifest*

  # Sync with AOSP
  $ANNOTATE $REPO init -u ${INIT_URL}/platform/manifest.git -b ${init_tag} \
      >${LOG_DIR}/sync_init 2>&1;
  $ANNOTATE $REPO sync -j8 >${LOG_DIR}/sync_aosp 2>&1; \

  # Put override to github, and sync again.
  mkdir .repo/local_manifests;
  echo "${local_manifest}" | tee ${LOG_DIR}/sync_override.xml \
      > .repo/local_manifests/override.xml;
  $ANNOTATE $REPO sync -j8 >${LOG_DIR}/sync_github 2>&1;

  # Checkout the head commit hash of each non-aosp repo.
  $REPO forall $dev_projects \
      -c 'git checkout $(git rev-parse $dev_refspec)' \
      >${LOG_DIR}/sync_checkout 2>&1;

  # Have to a reset --hard here!

  # If making for MAKO, then extract proprietary drivers.
  if echo "$lunch" | grep -q mako
  then
   tar -xvf /aosp/bin/mako_drivers.tar.gz >${LOG_DIR}/sync_drivers 2>&1;
  fi
fi

# Output the full code diff from init_tag to checked out code
# just for affected repos
mkdir ${LOG_DIR}/diffs
$REPO forall ${dev_projects} \
    -c "LOG_DIR=${LOG_DIR} /aosp/bin/jenkins_make_android_diff.sh"

# Output the latest commit hash for each project.
(
  $VERBOSE ls -la
  echo "================"
  $VERBOSE $REPO status 
  
  echo "================"
  $VERBOSE $REPO forall \
    -c 'echo $REPO_PROJECT && git log --pretty=oneline -n1 && echo "------"'
) > ${LOG_DIR}/sync_status 2>&1

) >${LOG_DIR}/SYNC 2>&1

print_log_url BUILD build_env build_clean build_api build_real
(
set -v
echo "lunch!"
source build/envsetup.sh
lunch $lunch

# Log execution environment after lunch.
( \
  env; \
  java -version 2>&1; \
  echo "======"; \
  prebuilts/misc/linux-x86/ccache/ccache -s; \
) >${LOG_DIR}/build_env

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

test ${FLAG_NO_CLOBBER} == "true" ||
    $ANNOTATE make clobber >${LOG_DIR}/build_clean 2>&1

test ${FLAG_UPDATE_API} == "false" ||  
    $ANNOTATE make update-api >${LOG_DIR}/build_api 2>&1

# Build android for real.
set +e
$ANNOTATE make -j8 >${LOG_DIR}/build_real 2>&1 
ret_code=$?
set -e

if [ $ret_code != 0 ]; then
  echo "======== LAST 100 lines of build log ======="
  tail -n 100 ${LOG_DIR}/build_real
  echo "============================================"
  exit 1 
fi

# Since we have 'set -e', SUCCESSFUL will only be created if above succeeds.
touch ${LOG_DIR}/SUCCESSFUL
) >${LOG_DIR}/BUILD 2>&1

print_log_url POST_BUILD
(
set -v
# Copy the 'out/' folder over to workspace,
# make sure this is persistent storage!
if [ ${FLAGS_copy_out} == "true" ]; then
  mkdir -p ${OUT_COPY_DIR}
  cp -r out ${OUT_COPY_DIR}
  touch ${LOG_DIR}/SUCCESSFUL-COPY
fi
) >${LOG_DIR}/POST_BUILD 2>&1

echo "${DONE_ASCII}"
trap - EXIT
