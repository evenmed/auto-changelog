
ALPHANUM_PUNCT_PATTERN="^[a-zA-Z0-9()?¿!¡*_-]"
EXCLUDED_EMOJIS_PATTERN="^(♻️|🚦|🎨|📦|🔖|🚧)"

##################################################################################
### STEP 1: Get the current version and latest commit message in the Changelog ###
##################################################################################

# Get the most recent 10 lines from the Changelog and put them in an array
FIRST_10_CL_LINES_STRING=$(head -n 10 dChangelog.md)
IFS=$'\n' read -rd '' -a FIRST_10_CL_LINES <<< "$FIRST_10_CL_LINES_STRING"

# Find the first one that starts with an emoji
for CL_LINE in "${FIRST_10_CL_LINES[@]}"
do
  if ! [[ $CL_LINE =~ $ALPHANUM_PUNCT_PATTERN ]]
  then
    LATEST_CL_COMMIT=$CL_LINE
    break
  fi
done

# Find the latest version number
VERSION_PATTERN="v([[:digit:]]+).([[:digit:]]+).([[:digit:]]+)"
V_MAJOR=0
V_MINOR=0
V_PATCH=0
for CL_LINE in "${FIRST_10_CL_LINES[@]}"
do
  if [[ $CL_LINE =~ $VERSION_PATTERN ]]
  then
    V_MAJOR=${BASH_REMATCH[1]}
    V_MINOR=${BASH_REMATCH[2]}
    V_PATCH=${BASH_REMATCH[3]}
    break
  fi
done

echo "LATEST_CL_COMMIT: $LATEST_CL_COMMIT"
echo "CURRENT VERSION: $V_MAJOR.$V_MINOR.$V_PATCH"

################################### END STEP 1 ###################################


##################################################################################
################ STEP 2: Get the commits to add to the changelog #################
##################################################################################

# Create an empty array where we'll store the commits to be added
COMMITS_TO_ADD=()

# Get the 100 most recent commit messages and put them in an array
COMMITS_STRING=$(git --no-pager log -100 HEAD --format="%s")
IFS=$'\n' read -rd '' -a COMMITS <<< "$COMMITS_STRING"

# Loop over them to find all that should be added
for COMMIT in "${COMMITS[@]}"
do
  echo "Checking $COMMIT"
  # If we get to the latest one from the cl, stop the loop
  if [[ $LATEST_CL_COMMIT == "$COMMIT"* ]]
  then
    break
  fi

  # Otherwise, check if it starts with a non-excluded emoji
  if ! [[ "$COMMIT" =~ $ALPHANUM_PUNCT_PATTERN ]] &&
     ! [[ "$COMMIT" =~ $EXCLUDED_EMOJIS_PATTERN ]]
  then
    # If it does, add it to the list
    COMMITS_TO_ADD+=("$COMMIT")
  fi
done

if ! [[ ${#COMMITS_TO_ADD[@]} > 0 ]]
then
  echo "No commits to add, exiting"
  exit 0
fi

for COMMIT in "${COMMITS_TO_ADD[@]}"
do
  echo "Adding: $COMMIT"
done
################################### END STEP 2 ###################################


##################################################################################
######## STEP 3: Calculate the new version number based on commits' emojis #######
##################################################################################

# Split commits into breaking changes, features, and patches
BREAKING_CHANGES=()
FEATURES=()
PATCHES=()
for COMMIT in "${COMMITS_TO_ADD[@]}"
do
  if [[ $COMMIT == "🚨"* ]]
  then
    BREAKING_CHANGES+=("$COMMIT")
  elif [[ $COMMIT == "✨"* ]]
  then
    FEATURES+=("$COMMIT")
  else
    PATCHES+=("$COMMIT")
  fi
done

# Increment the version accordingly
if [[ ${#BREAKING_CHANGES[@]} > 0 ]]
then
  V_MAJOR=$(($V_MAJOR + 1))
elif [[ ${#FEATURES[@]} > 0 ]]
then
  V_MINOR=$(($V_MINOR + 1))
else
  V_PATCH=$(($V_PATCH + 1))
fi

echo "NEW VERSION: $V_MAJOR.$V_MINOR.$V_PATCH"
################################### END STEP 3 ###################################


##################################################################################
########################## STEP 4: Update the Changelog! #########################
##################################################################################

# We start with the new version
STRING_TO_ADD="**v$V_MAJOR.$V_MINOR.$V_PATCH $(date '+%Y-%m-%d %H:%M')**  \n"

# Then we add the breaking changes at the top...
for COMMIT in "${BREAKING_CHANGES[@]}"
do
  STRING_TO_ADD+="$COMMIT  \n"
done

# ...followed by features...
for COMMIT in "${FEATURES[@]}"
do
  STRING_TO_ADD+="$COMMIT  \n"
done

# ...and lastly patches
for COMMIT in "${PATCHES[@]}"
do
  STRING_TO_ADD+="$COMMIT  \n"
done

# Finally, add it all into the changelog!
echo -e "$STRING_TO_ADD\n$(cat dChangelog.md)" > dChangelog.md

# Add the changelog update in the most recent commit
git commit --amend -C HEAD --no-verify dChangelog.md

################################### END STEP 4 ###################################