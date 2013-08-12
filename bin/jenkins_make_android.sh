#!/bin/bash
# Author: Kasturi Raghavan (kastur@gmail.com)

# Required args:
# (Usually provided by jenkin) JOB_NAME, BRANCH_JOB, BUILD_NUMBER
# init_tag
# dev_refspec
# local_manifest
# dev_projects
# lunch

set -e
set +xv

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

WARNING=' ***WARNING WARNING WARNING*** '

function log() {
  echo "$@" >&7
}

function fail() {
  log "${FAIL_ASCII}"
  exit 88
}

set -x
BUILD_DIR=/scratch/aosp/android  # used to have one job, now single place.
export TMPDIR=${BUILD_DIR}/tmp  # used by mktemp
LOCK_FILE=${BUILD_DIR}/LOCK
# Replace "/" in dev_refspec since we don't want to create nested directories.
JOB_BRANCH_NUM=${JOB_NAME}-${dev_refspec////_}-${BUILD_NUMBER}
LOG_DIR=$WORKSPACE/logs/${JOB_BRANCH_NUM}
OUT_COPY_DIR=$WORKSPACE/copy/${JOB_BRANCH_NUM}
PUBLIC_FQDN=android.0x72.com
JOB_URL=http://${PUBLIC_FQDN}:8080/job/${JOB_NAME}/

mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR}
rm -rf ${TMPDIR} && mkdir -p ${TMPDIR}
rm -rf ${LOG_DIR} && mkdir -p ${LOG_DIR}
# Put a symbolic link to the build directory in jenkins workspace.
rm -f $WORKSPACE/build_directory
ln -s ${BUILD_DIR} $WORKSPACE/build_directory
set +x

function logz_dir_url() {
  if [[ FLAG_interactive == "true" ]]; then
    log '--> logz_dir' $1 '<'${LOG_DIR}/$1'>'
  else
    log '--> logz_dir' $1 '<'${JOB_URL}ws/logs/${JOB_BRANCH_NUM}/$1'>'
  fi
  log  # newline.
}

function logz_url() {
  if [[ FLAG_interactive == "true" ]]; then
    log '--> logz' $1 '<'${LOG_DIR}/$1'>'
  else
    log '--> logz' $1 '<'${JOB_URL}ws/logs/${JOB_BRANCH_NUM}/$1/'*view*>'
  fi
}

if [[ FLAG_color == "true" ]]; then
  bold=`tput bold`
  normal=`tput sgr0`
  blue=`tput setaf 4`
fi

function logz() {
  log '---------------------------------------------------------------------'
  logfile="$1"
  command="${@:2}"
  log '+ ' "${bold}${blue}${command}${normal}"
  logz_url "${bold}${logfile}${normal}"
  eval "$command" 2>&1 | pv -tb -i10 2>&7 | tee -a ${LOG_DIR}/$1 \
      2>&1 >/dev/null
  ret=$?
  if [[ $ret != 0 ]]; then
    log "${bold}RETURN CODE=${ret}${normal}"
    log "=========== LAST 100 lines of $logfile ==========="
    tail -n 100 ${LOG_DIR}/$1 >&7
    log "=================================================="
    ls -lth ${LOG_DIR} >&7
    exit $ret
  fi
  log '---------------------------------------------------------------------'
  log
}

(
7<>`mktemp`  # Logs go here, i.e. later redirect fd=7 to a file.
trap 'fail' EXIT

log -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
log SYSTEM DASHBOARD : http://${PUBLIC_FQDN}:8000/cgi/dash
logz_dir_url
logz SETUP_ENV '(env; java -version)'
log -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

export LANG='en_US.UTF-8'  # The default ASCII encoding causes javac errors.
export USE_CCACHE=1
export CCACHE_DIR=/scratch/aosp/ccache

if [[ ${FLAG_nice} != "false" ]]; then
  log "$WARNING: Working in nice mode!"
  NICE="nice -n10"
fi

if [[ ${FLAG_debug_make} == "true" ]]; then
  MAKE_ARGS="showcommands V=1"
else
  MAKE_ARGS="-j8"
fi

REPO="$NICE /aosp/bin/repo"
ANNOTATE="annotate-output +%Y-%m-%d-%H:%M:%S.%N"
MAKE="$NICE $ANNOTATE make ${MAKE_ARGS}"  # optionally prefix with $ANNOTATE
FLOCK=flock  # used to lock the build directory.

if [[ FLAG_use_mirror == "true" &&
      -d /aosp/mirror/platform/manifest.git ]]; then
  INIT_URL=/aosp/mirror/platform/manifest.git
else
  INIT_URL=https://android.googlesource.com/platform/manifest
fi

# Acquire lock to prevent two builds on same BUILD_DIR.
log "Waiting for lock."
log "If stuck here (and you know for sure there are no other active jobs)"
log "go ahead and manually remove this file: ${LOCK_FILE}"
log
$FLOCK --wait=$(( 3600 * 3 )) 9  # Wait for upto 3 hours to obtain lock.
log "Acquired exclusive lock!"

logz_url METALOGZ_SYNC
(
if [[ ${FLAG_NO_SYNC} != "true" ]]; then

  # Remove .repo/local_manifest.xml and .repo/local_manifests directory.
  rm -rf .repo/local_manifest*

  logz sync_init $REPO init \
      -u ${INIT_URL} -b ${init_tag}
  logz sync_aosp $REPO sync -j8

  # Put override to github and sync again.
  mkdir .repo/local_manifests;
  echo "${local_manifest}" > .repo/local_manifests/override.xml
  logz sync_override_xml cat .repo/local_manifests/override.xml
  logz sync_github $REPO sync -j8

  #logz sync_fetch $REPO forall ${dev_projects} \
  #    -c git fetch

  # Checkout the head commit hash of each non-aosp repo.
  logz sync_checkout $REPO forall ${dev_projects} \
      -c git checkout ${dev_refspec}

  # TODO(krr): do a reset --hard here ?

  # If making for MAKO (NEXUS 4), then extract proprietary drivers.
  if echo "$lunch" | grep -q mako; then
   log "Extracting drivers for mako."
   logz sync_drivers tar -xvf /aosp/bin/mako_drivers.tar.gz
  fi

  # If making for MAGURO (GALAXY NEXUS), then extract proprietary drivers.
  if echo "$lunch" | grep -q maguro; then
   log "Extracting drivers for maguro."
   logz sync_drivers tar -xvf /aosp/bin/maguro_drivers.tar.gz
  fi

fi

# Do a git-diff ${init_tag}...${dev_refspec}
log "Doing a git diff ${init_tag}...${dev_refspec}"
mkdir ${LOG_DIR}/diffs
logz_dir_url diffs
$REPO forall ${dev_projects} \
    -c "LOG_DIR=${LOG_DIR} /aosp/bin/jenkins_make_android_diff.sh"
for diff_file in `ls ${LOGS_DIR}/diffs/*`; do
  logz_url /diffs/${diff_file}
done

# Output the latest commit hash for each project.
logz sync_finish_ls ls -la
log "Doing a repo status and git log -n1" >&7
logz sync_finish_repo_status $REPO status
logz sync_finish_gitlog $REPO forall \
    -c "'"'echo ${REPO_PROJECT} $(git log -n1 --pretty=oneline)'"'"
) >${LOG_DIR}/METALOGZ_SYNC 2>&1

logz_url METALOGZ_BUILD
(
log Doing lunch $lunch
source build/envsetup.sh
lunch $lunch

# Log execution environment after lunch.
log -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
logz BUILD_ENV 'env; java -version 2>&1;
                prebuilts/misc/linux-x86/ccache/ccache -s'
log -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

test ${FLAG_NO_CLOBBER} == "true" ||
    logz build_clean $MAKE clobber

test ${FLAG_UPDATE_API} == "false" ||
    logz build_api $MAKE update-api

if [[ ${FLAG_BUILD_SDK} == "true" ]]; then
    if [[ "$lunch" != "sdk-eng" ]]; then
      log "$WARNING: Expected lunch to be sdk-eng, but its '$lunch'"
    fi
    logz build_plain $MAKE
    logz build_sdk $MAKE sdk
else
    logz build_plain $MAKE
fi

# Since we have 'set -e', SUCCESSFUL will only be created if above succeeds.
touch ${LOG_DIR}/SUCCESSFUL
) >${LOG_DIR}/METALOGZ_BUILD 2>&1

logz_url METALOGZ_POSTBUILD
(
# Copy the 'out/' folder over to workspace,
# make sure this is persistent storage!
if [[ ${FLAG_copy_out} == "true" ]]; then
  mkdir -p ${OUT_COPY_DIR}
  cp -r out ${OUT_COPY_DIR}
  touch ${LOG_DIR}/SUCCESSFUL-COPY
fi
) >${LOG_DIR}/METALOGZ_POSTBUILD 2>&1

) 7>&1 9>${LOCK_FILE}

trap - EXIT
