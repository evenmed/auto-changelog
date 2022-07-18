# Potential issues:
# 1. If a commit msg contains another commit msg as a substring, eg:
#    - An old commit with msg "✨ Created github action for Changelog"
#    - A new commit with msg "✨ Created github action"
#    It will find the new one in the changelog and thus consider that it was
#    added, skipping it and any prior commits
# 
# 2. We only check the 100 most recent commits, so if more than 100 commits are
#    made without updating the changelog, the surplus won't get added
#
# 3. This is only triggered when pushing to main, meaning dev won't get the
#    changelog updates unless we downmerge / rebase. This also means that if we
#    manually commit any changes into the changelog in dev, we'll inevitably have
#    a conflict when merging into main


##################################################################################
############### STEP 1: Get the current version from the Changelog ###############
##################################################################################

# Regex to match "vX.X.X"
VERSION_PATTERN="v([[:digit:]]+).([[:digit:]]+).([[:digit:]]+)"
V_MAJOR=0
V_MINOR=0
V_PATCH=0

# Loop over Changelog lines until we find a version number
while IFS= read -r CL_LINE
do
  if [[ $CL_LINE =~ $VERSION_PATTERN ]]
  then
    V_MAJOR=${BASH_REMATCH[1]}
    V_MINOR=${BASH_REMATCH[2]}
    V_PATCH=${BASH_REMATCH[3]}
    break
  fi
done < dChangelog.md

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
ALPHANUM_PUNCT_PATTERN="^[a-zA-Z0-9()?¿!¡*_-]"
EXCLUDED_EMOJIS_PATTERN="^(♻️|🚦|🎨|📦|🔖|🚧)"
for COMMIT in "${COMMITS[@]}"
do
  # If we get to a commit already in the Changelog, stop the loop
  if [[ "$(cat dChangelog.md)" == *"$COMMIT"* ]]
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
  V_MINOR=0
  V_PATCH=0
elif [[ ${#FEATURES[@]} > 0 ]]
then
  V_MINOR=$(($V_MINOR + 1))
  V_PATCH=0
else
  V_PATCH=$(($V_PATCH + 1))
fi

NEW_VERSION="$V_MAJOR.$V_MINOR.$V_PATCH"
echo "NEW VERSION: $NEW_VERSION"
################################### END STEP 3 ###################################


##################################################################################
########################## STEP 4: Update the Changelog! #########################
##################################################################################

# We start with the new version
STRING_TO_ADD="**v$NEW_VERSION $(date '+%Y-%m-%d %H:%M')**  \n"

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

## Update version in package.json too
VERSION_PATTERN='"version": "[[:digit:]]+.[[:digit:]]+.[[:digit:]]+"'
if [[ "$(cat package.json)" =~ $VERSION_PATTERN ]]
then
  echo "Updating version in package.json"
  PACKAGE=$(cat package.json)
  echo -e "${PACKAGE/${BASH_REMATCH[0]}/"version": "$NEW_VERSION"}" > package.json
fi

# Push the changes into the repo
git config user.name "evenmed"
git config user.email "emilio@circular.co"
git add -A
git commit -m "Version $NEW_VERSION"
git push

# git commit --amend -C HEAD --no-verify dChangelog.md

################################### END STEP 4 ###################################