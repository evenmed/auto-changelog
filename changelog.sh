# Automatic Changelog Generator
#
# Version 2.0.0
#
# Description:
# This script takes care of updating the Changelog.md file with the latest
# commits whenever we push into main, and also updating the version both in the
# Changelog and in package.json, in accordance with what's described in the
# Changelog.README.md file.
#
# It consists of 4 steps:
#
# 1. Get the commits to add to the changelog. This is done by `git log`ing the 100
#    most recent commits' messages and then checking each one to see if:
#
#    a. They are already in the changelog, in which case we assume all prior
#       commits are too and stop the loop
#    b. If they start with an emoji that isn't any of the excluded ones
#    
#    If a. is false and b. is true, we push that commit into the list of commits
#    to be added into the changelog.
#
#    IMPORTANT: In order for the `git log` to work, the checkout step in the action
#    YAML file must have a "fetch-depth: 0". Otherwise the log will only return the
#    single most recent commit.
#
# 2. Calculate the new version number based on commits' emojis. We split the list
#    of commits to add into 3:
#
#    - *Breaking Changes* are all commits that start with a "🚨"
#    - *Features* are all commits that start with a "✨"
#    - *Patches* are all other commits
#
#    If there are any Breaking Changes, we do a MAJOR version bump. If there aren't
#    any Breaking Changes but there are any Features, we do a MINOR bump. If they're
#    all patches, we do a PATCH version bump.
#
# 3. Update the Changelog! We generate a string to be added at the top of the
#    changelog in the following format:
#    
#    **vX.X.X YYYY-MM-DD HH:MM**
#    ...All breaking changes
#    ...All new features
#    ...All patches
#
#    Once that's done, we add it into the top of the Changelog file. Additionally,
#    we also update the version in package.json during this step
#
#
# Potential issues:
# 1. If we repeat identical commit messages, eg:
#    - An old commit with msg "🐞 Fixed bug"
#    - A new commit with msg "🐞 Fixed bug"
#    It will find the new one in the changelog and thus consider that it was
#    added, skipping it and any prior commits
# 
# 2. We only check the 100 most recent commits, so if more than 100 commits are
#    made without updating the changelog, the surplus won't get added
#
# 3. This is only triggered when pushing to main, meaning dev won't get the
#    changelog updates unless we downmerge / rebase. This also means that if we
#    manually commit any changes into the changelog in dev, we'll likely have a
#    conflict when merging into main
#
# 4. Since this script is triggered by a push into main and it also pushes into
#    main itself, there's the danger of creating an infinite action loop. Per
#    initial tests, it seems that the push from this action doesn't trigger the
#    action, probably thanks to a safeguard from Github for this exact scenario.
#    Additionally, if it did get triggered a 2nd time, it shouldn't find any new
#    commits to add into the Changelog and thus not get triggered a third time.


##################################################################################
################ STEP 1: Get the commits to add to the changelog #################
##################################################################################

# Create an empty array where we'll store the commits to be added
COMMITS_TO_ADD=()

# Get the 100 most recent commit messages and put them in an array
COMMITS_STRING=$(git --no-pager log -100 HEAD --format="%s")
IFS=$'\n' read -rd '' -a COMMITS <<< "$COMMITS_STRING"

# Loop over them to find all that should be added
ALPHANUM_PUNCT_PATTERN="^[a-zA-Z0-9()?¿!¡*_-]"
EXCLUDED_EMOJIS_PATTERN="^(♻️|🚦|🎨|📦|🔖|🚧)"
CHANGELOG_CONTENT=$(cat dChangelog.md)
for COMMIT in "${COMMITS[@]}"
do
  # If we get to a commit already in the Changelog, stop the loop
  # To avoid matching commits which are substrings of others, we use a pattern to
  # ensure that there's a newline after the commit in the Changelog
  COMMIT_PATTERN="$COMMIT *
"
  if [[ "$CHANGELOG_CONTENT" =~ $COMMIT_PATTERN ]]
  then
    break
  fi

  # Otherwise, check if it starts with a non-excluded emoji
  if ! [[ "$COMMIT" =~ $ALPHANUM_PUNCT_PATTERN ]] &&
     ! [[ "$COMMIT" =~ $EXCLUDED_EMOJIS_PATTERN ]]
  then
    # If it does, add it to the list
    echo "Adding: $COMMIT"
    COMMITS_TO_ADD+=("$COMMIT")
  fi
done

if ! [[ ${#COMMITS_TO_ADD[@]} > 0 ]]
then
  echo "No commits to add, exiting"
  exit 0
fi

################################### END STEP 1 ###################################


##################################################################################
######## STEP 2: Calculate the new version number based on commits' emojis #######
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
  NEW_VERSION=$(npm --no-git-tag-version version major)
elif [[ ${#FEATURES[@]} > 0 ]]
then
  NEW_VERSION=$(npm --no-git-tag-version version minor)
else
  NEW_VERSION=$(npm --no-git-tag-version version patch)
fi

echo "NEW VERSION: $NEW_VERSION"

################################### END STEP 2 ###################################


##################################################################################
########################## STEP 3: Update the Changelog! #########################
##################################################################################

# We start with the new version and date
STRING_TO_ADD="**$NEW_VERSION $(date '+%Y-%m-%d %H:%M')**  \n"

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
echo -e "$STRING_TO_ADD\n$CHANGELOG_CONTENT" > dChangelog.md

# Push the changes into the repo
git config user.name "evenmed"
git config user.email "emilio@circular.co"
git add -A
git commit -m "Version $NEW_VERSION"
git push

################################### END STEP 3 ###################################