#!/bin/bash

# Set before release
VERSION="0.1.0"

# Default values
API_KEY=""
PROJECT_ID=""
IS_CI="false"
PARAM_CI=""
SKIP_GIT="false"
FAIL_ON_ERROR="false"
COMMIT_ID=""
COMMIT_MESSAGE=""
COMMIT_AUTHOR=""

# Print header and version
cat << EOF

 ______ _                _____           
|  ____| |              / ____|  v.$VERSION        
| |__  | | _____      _| |     _____   __
|  __| | |/ _ \ \ /\ / / |    / _ \ \ / /
| |    | | (_) \ V  V /| |___| (_) \ V / 
|_|    |_|\___/ \_/\_/  \_____\___/ \_/  


EOF

# Show the help screen
show_help() {
cat << EOF

                      FlowCov Bash $VERSION

             Report uploading tool for FlowCov.io
           Documentation at https://flowcov.io/docs
    Contribute at https://github.com/FlowSquad/flowcov-bash


    --api-key <API_KEY>         The API key to use (required)
    --project-id <PROJECT_ID>   The project to use (required)
    --ci                        Override the CI detection result
    --no-ci                     Override the CI detection result
    --no-git                    Do not include commit and repo information
    --fail-on-error             Fail the script if the upload fails
    --commit-id <COMMIT_ID>     Override the commit id to upload
    --commit-message <MSG>      Override the commit message to upload
    --commit-author <AUTHOR>    Override the commit author to upload
    --repo-url <URL>            Override the remote repository url to upload
    --branch-name <BRANCH>      Override the remote branch name to upload
    --help                      Display this help and exit

EOF
}


while test $# != 0
do
    case "$1" in
        --help)
            # Call help function and exit
            show_help;
            exit 0;
            ;;
        --api-key)
            API_KEY=$2;
            ;;
        --project-id)
            PROJECT_ID=$2;
            ;;
        --ci)
            PARAM_CI="true";
            ;;
        --no-ci)
            PARAM_CI="false";
            ;;
        --no-git)
            SKIP_GIT="true";
            ;;
        --fail-on-error)
            FAIL_ON_ERROR="true";
            ;;
        --commit-id)
            COMMIT_ID=$2;
            ;;
        --commit-message)
            COMMIT_MESSAGE=$2;
            ;;
        --commit-author)
            COMMIT_AUTHOR=$2;
            ;;
        --repo-url)
            REPO_URL=$2;
            ;;
        --branch-name)
            BRANCH_NAME=$2;
            ;;
    esac
    shift
done

if [ -z "$API_KEY" ];
then echo "Your API key is required, but none was specified. You can find your API key in the project settings. Add it via the --api-key parameter." && exit 1;
fi;

if [ -z "$PROJECT_ID" ];
then echo "Your project ID is required, but none was specified. You can find your project ID in the project settings. Add it via the --project-id parameter." && exit 1;
fi;


# Check if CI environment
# Only try auto detection if no flag was specified
if [ -z "$PARAM_CI" ];
then
    # Source: https://github.com/watson/ci-info/blob/master/index.js#L53-L56
    #   env.CI                      // Travis CI, CircleCI, Cirrus CI, Gitlab CI, Appveyor, CodeShip, dsari
    #   env.CONTINUOUS_INTEGRATION  // Travis CI, Cirrus CI
    #   env.BUILD_NUMBER            // Jenkins, TeamCity
    #   env.RUN_ID                  // TaskCluster, dsari
    if [ ! -z "$CI" ] || [ ! -z "$CONTINUOUS_INTEGRATION" ] || [ ! -z "$BUILD_NUMBER" ] || [ ! -z "$RUN_ID" ]; 
        then
            echo "CI detected. You can override this with the --no-ci flag.";
            IS_CI="true";
        else echo "No CI detected. You can override this with the --ci flag.";
    fi;
else
    # Flag --ci or --no-ci was specified
    if [ "$PARAM_CI" = "true" ];
        then echo "Detected --ci flag, using CI mode.";
        else echo "Detected --no-ci flag, using non-CI mode.";
    fi;

    # Use parameter value
    IS_CI="$PARAM_CI";
fi;


# Check if git is available    
git --version 2>&1 >/dev/null;
GIT_IS_AVAILABLE=$?;


# If git is available, commit information can be added to report
if [ $GIT_IS_AVAILABLE -eq 0 ];
then
    if [ $SKIP_GIT = "true" ];
    then
        # Flag was specified
        echo "Detected flag --no-git, not adding commit information to report.";
    else
        # No flag was specified and git is available
        echo "Adding commit information to report. You can prevent this with the --no-git flag.";
        [ -z $COMMIT_ID ] && COMMIT_ID=$(git rev-parse --short HEAD);
        [ -z $COMMIT_MESSAGE ] && COMMIT_MESSAGE=$(git log --format=%B -n 1 $COMMIT_ID);
        [ -z $COMMIT_AUTHOR ] && COMMIT_AUTHOR=$(git show -s --format='%an <%ae>' $COMMIT_ID);
        [ -z $REPO_URL ] && REPO_URL=$(git config --get remote.origin.url);
        [ -z $BRANCH_NAME ] && BRANCH_NAME=$(git rev-parse --abbrev-ref --symbolic-full-name @{u});
    fi;
else 
    # Git is not available
    echo "Could not find git on path, not adding commit information to report.";
    SKIP_GIT="true";
fi;

# Find all matching files in all subdirs, then join their content with a comma as separator
value=$(find . -name 'flowCovReport.json' -print0 | xargs -I{} -0 sh -c '{ cat {}; echo ,; }');

# Remove the last comma by reversing the string, removing the first char, and reversing it again
value=$(echo $value | rev | cut -c 2- | rev);

# Create the json array with the now comma-separated list of reports
if [ $SKIP_GIT = "false" ];
then
    value="{'repoUrl':'$REPO_URL','branchName':'$BRANCH_NAME','projectId':'$PROJECT_ID','ci':'$IS_CI','commitId':'$COMMIT_ID','commitMessage':'$COMMIT_MESSAGE','commitAuthor': '$COMMIT_AUTHOR','data':[$value]}";
else
    value="{'projectId':'$PROJECT_ID','ci':'$IS_CI','data':[$value]}";
fi;

# Replace single quotes with double quotes
value=$(echo $value | sed "s/'/\"/g");

# Push them to the server
result=$(curl --write-out "%{http_code}" --silent --output /dev/null -H "Content-Type: application/json" -X POST -d "$value" "https://app.flowcov.io/api/v0/run?apiKey=$API_KEY");

# Check if response code was 200
if [ $result -eq 200 ];
then
    echo "Successfully uploaded report.";
    exit 0;
else 
    echo "Failed to upload report with status code $result.";
    if [ $FAIL_ON_ERROR = "true" ];
    then exit 1;
    else exit 0;
    fi;
fi;