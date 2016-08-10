#!/bin/bash -e

function usage() {
  echo "Usage: jjb.sh COMMAND [JOB_NAME...]"
  echo
  echo "Commands:"
  echo "    test    Check the grammatical problems"
  echo "    update  Generate jenksin jobs"
  echo "    help    Show this messages"
  echo
  echo "Job Names:"
  echo "    If you do not specifie the job name, update or test target is all jobs."
  echo "    You can use regular expression to the job name."
}

# Check argument
case $1 in
test|update)
  mode=$1
  shift
  ;;
help)
  usage
  exit 0
  ;;
*)
  echo "Please set command" && echo
  usage
  exit 1
esac

# Check environment
[ -z $JENKINS_USER ] && { echo "Please set \$JENKINS_USER"; exit 1; }
[ -z $JENKINS_TOKEN ] && { echo "Please set \$JENKINS_TOKEN"; exit 1; }
[ -z $JENKINS_URL ] && { echo "Please set \$JENKINS_URL"; exit 1; }

# Check command
if [ $mode = 'update' ]; then
  type wget >/dev/null 2>&1 ||\
    { echo >&2 "wget is not installed. Aborting."; exit 1; }
  type parallel >/dev/null 2>&1 ||\
    { echo >&2 "GNU Parallel is not installed. Aborting."; exit 1; }
fi

# Generate temporary directory to output jobs
tempdir=`mktemp -d`
tempyaml=$tempdir/all.yml
out=$tempdir/out
mkdir $out

function cleanup() {
  echo "cleanup temporary directory"
  rm -fr $tempdir
}
trap 'cleanup' EXIT

# Generate configuration file
cat <<EOF > $tempdir/jjb.ini
[jenkins]
user=$JENKINS_USER
password=$JENKINS_TOKEN
url=$JENKINS_URL

[job_builder]
include_path=scripts
recursive=True
allow_duplicates=True
ignore_cache=True
EOF

# Generate jobs from YAML file
cat jobs/default/*.yml > $tempyaml
find jobs -name "*.yml" -type f |\
  sort |\
  grep -v default/ |\
  xargs cat >> $tempyaml

jenkins-jobs --conf $tempdir/jjb.ini test $tempyaml $@ -o $out


case $mode in
# Update job on Jenkins
update)
  ls $out | parallel --gnu -k -j 5 "echo {} | jenkins-jobs --conf $tempdir/jjb.ini update $tempyaml {}"
  ;;
test)
  if [ ! -d output/test ]; then
    mkdir -p output/test
  fi

  rm -fr output/test/*
  cp -fr $out/* output/test
  echo output/test
  ;;
esac
