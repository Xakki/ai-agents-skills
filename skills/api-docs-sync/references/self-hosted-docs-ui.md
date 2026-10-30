# Self-hosted documentation UI assets

Establish whether acceptance requires no automatic third-party page requests, no UI download during image build, a specific upstream version, or an entirely offline image rebuild. These are distinct claims; clarify a material ambiguity before treating any one as satisfied.

Use the approved source and a pinned prebuilt distribution when appropriate. Verify source metadata and integrity; retain licenses, notices and provenance for selected files. Distinguish original archive integrity from installed or modified file hashes. Do not silently modify a third-party bundle or add another source outside authorization.

Serve exact approved assets using the project's actual route and authorization policy; check each page independently for expected scripts, styles, schema references and decorative assets. Disable optional external validators, fonts and other unwanted network requests without weakening protected routes.

Run the supported project tests and observe real rendered pages with network and error recording started before navigation. Record the observation window, visible operation content, relevant statuses, third-party requests and runtime errors. Verify served asset bytes and, when claiming image packaging, that a source bind mount did not mask missing image contents. A successful HTML response or failed third-party request alone is not proof of a working offline UI.

After the last asset or configuration change, rerun the required focused checks. Record actual evidence, remaining limitations and complete provenance; preserve staged work and use the authorized Git workflow if a commit is requested.
