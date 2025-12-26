Working with push protection from the command line
Learn your options for unblocking your push from the command line to GitHub if secret scanning detects a secret in your changes.

Who can use this feature?
Users with write access

In this article
About push protection from the command line
Push protection prevents you from accidentally committing secrets to a repository by blocking pushes containing supported secrets.

When you attempt to push a supported secret from the command line to a repository secured by push protection, GitHub will block the push.

You should either:

Remove the secret from your branch. For more information, see Resolving a blocked push.
Follow a provided URL to see what options are available to you to allow the push. For more information, see Bypassing push protection and Requesting bypass privileges.
Up to five detected secrets will be displayed at a time on the command line. If a particular secret has already been detected in the repository and an alert already exists, GitHub will not block that secret.

If you confirm a secret is real and that you intend to fix it later, you should aim to remediate the secret as soon as possible. For example, you might revoke the secret and remove the secret from the repository's commit history. Real secrets that have been exposed must be revoked to avoid unauthorized access. You might consider first rotating the secret before revoking it. For more information, see Removing sensitive data from a repository.

Note

If your Git configuration supports pushes to multiple branches, and not only to the current branch, your push may be blocked due to additional and unintended refs being pushed. For more information, see the push.default options in the Git documentation.
If secret scanning upon a push times out, GitHub will still scan your commits for secrets after the push.
Resolving a blocked push
To resolve a blocked push, you must remove the secret from all of the commits it appears in.

If the secret was introduced by your latest commit, see Removing a secret introduced by the latest commit on your branch.
If the secret appears in earlier commits, see Removing a secret introduced by an earlier commit on your branch.
Note

To learn how to resolved a blocked commit in the GitHub UI, see Working with push protection in the GitHub UI.

Removing a secret introduced by the latest commit on your branch
If the blocked secret was introduced by the latest commit on your branch, you can follow the guidance below.

Remove the secret from your code.
To commit the changes, run git commit --amend --all. This updates the original commit that introduced the secret instead of creating a new commit.
Push your changes with git push.
Removing a secret introduced by an earlier commit on your branch
You can also remove the secret if the secret appears in an earlier commit in the Git history. To do so, you will need to identify which commit first introduced the secret and modify the commit history with an interactive rebase.

Examine the error message that displayed when you tried to push your branch, which lists all of the commits that contain the secret.

remote:   —— GitHub Personal Access Token ——————————————————————
remote:    locations:
remote:      - commit: 8728dbe67
remote:        path: README.md:4
remote:      - commit: 03d69e5d3
remote:        path: README.md:4
remote:      - commit: 8053f7b27
remote:        path: README.md:4
Next, run git log to see a full history of all the commits on your branch, along with their corresponding timestamps.

test-repo (test-branch)]$ git log
commit 8053f7b27 (HEAD -> main)
Author: Octocat <1000+octocat@users.noreply.github.com
Date:   Tue Jan 30 13:03:37 2024 +0100

  my fourth commit message

commit 03d69e5d3
Author: Octocat <1000+octocat@users.noreply.github.com>
Date:   Tue Jan 30 13:02:59 2024 +0100

  my third commit message

commit 8728dbe67
Author: Octocat <1000+octocat@users.noreply.github.com
Date:   Tue Jan 30 13:01:36 2024 +0100

  my second commit message

commit 6057cbe51
Author: Octocat <1000+octocat@users.noreply.github.com
Date:   Tue Jan 30 12:58:24 2024 +0100

  my first commit message

Focusing only on the commits that contain the secret, use the output of git log to identify which commit comes earliest in your Git history.

In the example, commit 8728dbe67 was the first commit to contain the secret.
Start an interactive rebase with git rebase -i <COMMIT-ID>~1.

For <COMMIT-ID>, use the commit identified in step 3. For example, git rebase -i 8728dbe67~1.
In the editor, choose to edit the commit identified in step 3 by changing pick to edit on the first line of the text.

edit 8728dbe67 my second commit message
pick 03d69e5d3 my third commit message
pick 8053f7b27 my fourth commit message
Save and close the editor to start the interactive rebase.

Remove the secret from your code.

Add your changes to the staging area using git add ..

Note

The full command is git add .:

There is a space between add and ..
The period following the space is part of the command.
Commit your changes using git commit --amend.

Run git rebase --continue to finish the rebase.

Push your changes with git push.

Bypassing push protection
If GitHub blocks a secret that you believe is safe to push, you may be able to bypass the block by specifying a reason for allowing the secret to be pushed.

When you allow a secret to be pushed, an alert is created in the Security tab. GitHub closes the alert and doesn't send a notification if you specify that the secret is a false positive or used only in tests. If you specify that the secret is real and that you will fix it later, GitHub keeps the security alert open and sends notifications to the author of the commit, as well as to repository administrators. For more information, see Managing alerts from secret scanning.

When a contributor bypasses a push protection block for a secret, GitHub also sends an email alert to the organization owners, security managers, and repository administrators who have opted in for email notifications.

If you don't see the option to bypass the block, the repository administrator or organization owner has configured tighter controls around push protection. Instead, you should remove the secret from the commit, or submit a request for "bypass privileges" in order to push the blocked secret. For more information, see Requesting bypass privileges.

Visit the URL returned by GitHub when your push was blocked, as the same user that performed the push. If a different user attempts to visit this URL, they will receive a 404 error.

Choose the option that best describes why you should be able to push the secret.

If the secret is only used in tests and poses no threat, click It's used in tests.

If the detected string is not a secret, click It's a false positive.

If the secret is real but you intend to fix it later, click I'll fix it later.

Note

You are required to specify a reason for bypassing push protection if the repository has secret scanning enabled.

When pushing to a public repository that doesn't have secret scanning enabled, you are still protected from accidentally pushing secrets thanks to push protection for users, which is on by default for your user account.

With push protection for users, GitHub will automatically block pushes to public repositories if these pushes contain supported secrets, but you won't need to specify a reason for allowing the secret, and GitHub won't generate an alert. For more information, see Push protection for users.

Click Allow me to push this secret.

Reattempt the push on the command line within three hours. If you have not pushed within three hours, you will need to repeat this process.

Requesting bypass privileges
If your push has been blocked by push protection and you believe the secret is safe to push, you can request permission to bypass the block. Your request is sent to a designated group of reviewers, who will either approve or deny the request.

Requests expire after 7 days.

Visit the URL returned by GitHub when your push was blocked, as the same user that performed the push. If a different user attempts to visit this URL, they will receive a 404 error.
Under "Or request bypass privileges", add a comment. For example, you might explain why you believe the secret is safe to push, or provide context about the request to bypass the block.
Click Submit request.
Check your email notifications for a response to your request.
Once your request has been reviewed, you will receive an email notifying you of the decision.

If your request is approved, you can push the commit (or commits) containing the secret to the repository, as well as any future commits that contain the same secret.

If your request is denied, you will need to remove the secret from all commits containing the secret before pushing again. For information on how to remove a blocked secret, see Resolving a blocked push.

Further reading
Working with push protection in the GitHub UI
Working with push protection from the REST API
