# OnSpeak Agent Policy

## Publication is opt-in

Never publish or deploy OnSpeak as an inferred final step. This applies to
every agent, chat, and session working in this repository.

- Do **not** push a branch or tag, create or edit a GitHub Release, dispatch a
  release or deployment workflow, upload release artifacts, publish GitHub
  Pages, or install a newly built app unless the user explicitly asks for that
  external action in the current chat.
- “Complete the work”, “finish”, “build”, “test”, “prepare a release”, or a
  version/changelog edit do **not** authorize publication.
- To publish a release, first show the exact version and release notes, then
  wait for a separate, explicit confirmation such as: “Publish v0.8.0 now.”
- Do not modify `README.md`, `CHANGELOG.md`, a version number, or release
  configuration solely because an implementation task is complete. Change
  them only when the user explicitly requests the relevant documentation or
  release-preparation work.

## Required release gate

The release workflow also requires the GitHub repository variable
`ONSPEAK_RELEASE_APPROVED_TAG` to exactly equal the tag being released. A
maintainer must set that value immediately before an explicitly approved
release and clear it afterwards. This is a second safeguard; it does not
replace the explicit user approval above.
