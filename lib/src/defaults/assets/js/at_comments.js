(() => {
  // src/at_comments.js
  var AtCommentsWidget = class {
    constructor(containerId, uri, appViewUrl, turnstileSiteKey) {
      this.container = document.getElementById(containerId);
      this.uri = uri;
      this.appViewUrl = appViewUrl || "https://public.api.bsky.app";
      this.turnstileSiteKey = turnstileSiteKey;
      this.threadData = null;
      this.turnstileWidgetId = null;
      this.postRkey = uri.split("/").pop();
      this.replyToPost = null;
    }
    async load() {
      if (!this.container || !this.uri) {
        console.warn("AtComments: Missing container or URI");
        return;
      }
      await this.loadComments();
    }
    async loadComments() {
      try {
        const cacheBust = Date.now();
        const url = `${this.appViewUrl}/xrpc/app.bsky.feed.getPostThread?uri=${encodeURIComponent(this.uri)}&depth=10&_t=${cacheBust}`;
        const response = await fetch(url, {
          cache: "no-store",
          headers: {
            "Cache-Control": "no-cache"
          }
        });
        if (!response.ok) {
          throw new Error(`Failed to fetch comments: ${response.status}`);
        }
        const data = await response.json();
        this.threadData = data.thread;
        const rootAuthor = this.threadData?.post?.author?.handle;
        console.log("AtComments: Thread data loaded", {
          uri: this.uri,
          replyCount: this.threadData?.post?.replyCount,
          repliesCount: this.threadData?.replies?.length,
          rootAuthor
        });
        if (rootAuthor && this.threadData?.replies?.length < this.threadData?.post?.replyCount) {
          console.log("AtComments: Fetching additional replies from root author");
          const authorReplies = await this.fetchAuthorReplies(rootAuthor);
          if (authorReplies && authorReplies.length > 0) {
            try {
              this.buildThreadTree(authorReplies);
            } catch (error) {
              console.error("AtComments: Error building thread tree:", error);
            }
          }
        }
        this.container.innerHTML = "";
        this.renderCommentForm();
        if (this.threadData && this.threadData.replies) {
          const threadContainer = document.createElement("div");
          threadContainer.className = "at-comments-thread";
          this.renderReplies(this.threadData.replies, threadContainer, 0);
          this.container.appendChild(threadContainer);
        }
      } catch (error) {
        console.error("Error loading comments:", error);
        this.container.innerHTML = "";
        this.renderCommentForm();
        this.showStatus("Failed to load comments", "error");
      }
    }
    renderReplies(replies, container, depth = 0) {
      if (!replies || replies.length === 0) return;
      replies.forEach((reply) => {
        if (reply.post) {
          const commentEl = this.createCommentElement(reply.post, depth);
          container.appendChild(commentEl);
          if (reply.replies && reply.replies.length > 0) {
            const nestedContainer = document.createElement("div");
            nestedContainer.className = "at-comment-replies";
            this.renderReplies(reply.replies, nestedContainer, depth + 1);
            commentEl.appendChild(nestedContainer);
          }
        }
      });
    }
    async fetchAuthorReplies(author) {
      try {
        const url = `${this.appViewUrl}/xrpc/app.bsky.feed.getAuthorFeed?actor=${author}&filter=posts_with_replies&limit=50`;
        const response = await fetch(url, {
          cache: "no-store"
        });
        if (!response.ok) {
          console.warn("AtComments: Failed to fetch author replies");
          return [];
        }
        const data = await response.json();
        const authorReplies = data.feed.map((item) => item.post).filter((post) => {
          const reply = post.record?.reply;
          if (!reply) return false;
          return reply.root.uri === this.uri || reply.parent.uri === this.uri;
        });
        console.log(`AtComments: Found ${authorReplies.length} replies from ${author}`);
        if (authorReplies.length > 0 && this.threadData.replies) {
          const existingUris = new Set(
            this.threadData.replies.map((r) => r.post?.uri).filter(Boolean)
          );
          return authorReplies.filter((post) => !existingUris.has(post.uri));
        }
        return authorReplies;
      } catch (error) {
        console.error("AtComments: Error fetching author replies:", error);
        return [];
      }
    }
    buildThreadTree(newPosts) {
      const postMap = /* @__PURE__ */ new Map();
      if (this.threadData.replies) {
        const addRecursive = (replies) => {
          replies.forEach((r) => {
            if (r.post) {
              postMap.set(r.post.uri, r);
              if (r.replies && r.replies.length > 0) {
                addRecursive(r.replies);
              }
            }
          });
        };
        addRecursive(this.threadData.replies);
      }
      newPosts.forEach((post) => {
        if (!postMap.has(post.uri)) {
          postMap.set(post.uri, {
            $type: "app.bsky.feed.defs#threadViewPost",
            post,
            replies: []
          });
        }
      });
      const topLevel = [];
      const nested = [];
      postMap.forEach((threadViewPost) => {
        const parentUri = threadViewPost.post.record?.reply?.parent.uri;
        if (!parentUri) {
          console.warn("AtComments: Post without parent URI:", threadViewPost.post.uri);
          return;
        }
        if (parentUri === this.uri) {
          topLevel.push(threadViewPost);
        } else {
          nested.push(threadViewPost);
        }
      });
      nested.forEach((threadViewPost) => {
        const parentUri = threadViewPost.post.record?.reply?.parent.uri;
        const parent = postMap.get(parentUri);
        if (parent && parent.replies) {
          parent.replies.push(threadViewPost);
        } else {
          console.warn("AtComments: Parent not found for reply:", threadViewPost.post.uri, "parent:", parentUri);
        }
      });
      topLevel.sort(
        (a, b) => new Date(a.post.record.createdAt) - new Date(b.post.record.createdAt)
      );
      this.threadData.replies = topLevel;
      console.log(`AtComments: Rebuilt thread tree with ${postMap.size} total posts, ${topLevel.length} top-level`);
    }
    formatDate(isoString) {
      const date = new Date(isoString);
      return date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
      });
    }
    createCommentElement(post, depth = 0) {
      const div = document.createElement("div");
      div.className = "at-comment";
      if (depth > 0 && depth <= 5) {
        div.classList.add(`at-comment-depth-${depth}`);
      }
      const record = post.record;
      const commentText = record.text;
      const formattedDate = this.formatDate(record.createdAt);
      div.innerHTML = `
      <div class="at-comment-date">${this.escapeHtml(formattedDate)}</div>
      <div class="at-comment-body">${this.escapeHtml(commentText)}</div>
      <button class="at-comment-reply-btn" data-uri="${post.uri}" data-text="${this.escapeHtml(commentText)}">
        Reply
      </button>
    `;
      const replyBtn = div.querySelector(".at-comment-reply-btn");
      if (replyBtn) {
        replyBtn.addEventListener("click", () => this.setReplyTo(post.uri, commentText));
      }
      return div;
    }
    renderCommentForm() {
      let formContainer = this.container.querySelector(".at-comment-form-container");
      if (!formContainer) {
        formContainer = document.createElement("div");
        formContainer.className = "at-comment-form-container";
        this.container.insertBefore(formContainer, this.container.firstChild);
      }
      const replyToHtml = this.replyToPost ? `
      <div class="at-comment-replying-to">
        <span>Replying to: <em>"${this.escapeHtml(this.replyToPost.text)}"</em></span>
        <button type="button" id="at-comment-cancel-reply" class="at-comment-cancel-reply">Cancel</button>
      </div>
    ` : "";
      formContainer.innerHTML = `
      <div class="at-comment-form">
        <h3>Leave a Comment</h3>
        ${replyToHtml}
        <div class="at-comment-form-fields">
          <input
            type="text"
            id="at-comment-name"
            placeholder="Your name"
            maxlength="50"
            class="at-comment-input"
            required>
          <textarea
            id="at-comment-textarea"
            placeholder="Write a comment..."
            maxlength="280"
            rows="3"
            class="at-comment-input"></textarea>
          <div class="at-comment-form-footer">
            <span class="at-comment-char-count">0/280</span>
          </div>
          <div id="at-comment-turnstile" class="at-comment-turnstile"></div>
          <button class="at-comment-submit-btn" id="at-comment-submit" disabled>
            Post Comment
          </button>
        </div>
        <p class="at-comment-note">Comments are posted to <a href="https://bsky.app" target="_blank">Bluesky</a></p>
      </div>
      <div class="at-comment-form-status"></div>
    `;
      this.setupFormListeners(formContainer);
      this.renderTurnstile();
    }
    setupFormListeners(formContainer) {
      const nameInput = document.getElementById("at-comment-name");
      const textarea = document.getElementById("at-comment-textarea");
      const submitBtn = document.getElementById("at-comment-submit");
      const charCount = formContainer.querySelector(".at-comment-char-count");
      const cancelReplyBtn = document.getElementById("at-comment-cancel-reply");
      const updateSubmitState = () => {
        const hasName = nameInput.value.trim().length > 0;
        const hasText = textarea.value.trim().length > 0;
        const hasTurnstile = this.getTurnstileToken() !== null;
        submitBtn.disabled = !(hasName && hasText && hasTurnstile);
      };
      if (textarea) {
        textarea.addEventListener("input", (e) => {
          const length = e.target.value.length;
          charCount.textContent = `${length}/280`;
          updateSubmitState();
        });
      }
      if (nameInput) {
        nameInput.addEventListener("input", updateSubmitState);
      }
      if (submitBtn) {
        submitBtn.addEventListener("click", () => this.postComment());
      }
      if (cancelReplyBtn) {
        cancelReplyBtn.addEventListener("click", () => this.cancelReply());
      }
      this.updateSubmitState = updateSubmitState;
    }
    renderTurnstile() {
      if (!this.turnstileSiteKey) {
        console.warn("AtComments: No Turnstile site key provided");
        return;
      }
      const container = document.getElementById("at-comment-turnstile");
      if (!container) return;
      const renderWidget = () => {
        if (typeof turnstile !== "undefined") {
          this.turnstileWidgetId = turnstile.render(container, {
            sitekey: this.turnstileSiteKey,
            callback: () => {
              if (this.updateSubmitState) this.updateSubmitState();
            },
            "expired-callback": () => {
              if (this.updateSubmitState) this.updateSubmitState();
            }
          });
        } else {
          setTimeout(renderWidget, 100);
        }
      };
      renderWidget();
    }
    getTurnstileToken() {
      if (typeof turnstile !== "undefined" && this.turnstileWidgetId !== null) {
        return turnstile.getResponse(this.turnstileWidgetId);
      }
      return null;
    }
    resetTurnstile() {
      if (typeof turnstile !== "undefined" && this.turnstileWidgetId !== null) {
        turnstile.reset(this.turnstileWidgetId);
      }
    }
    setReplyTo(uri, text) {
      this.replyToPost = { uri, text };
      this.renderCommentForm();
      const formContainer = this.container.querySelector(".at-comment-form-container");
      if (formContainer) {
        formContainer.scrollIntoView({ behavior: "smooth", block: "center" });
      }
      const textarea = document.getElementById("at-comment-textarea");
      if (textarea) {
        textarea.focus();
      }
    }
    cancelReply() {
      this.replyToPost = null;
      this.renderCommentForm();
    }
    async postComment() {
      const nameInput = document.getElementById("at-comment-name");
      const textarea = document.getElementById("at-comment-textarea");
      const displayName = nameInput?.value.trim();
      const text = textarea?.value.trim();
      const turnstileToken = this.getTurnstileToken();
      if (!displayName) {
        this.showStatus("Please enter your name", "error");
        return;
      }
      if (!text) {
        this.showStatus("Comment cannot be empty", "error");
        return;
      }
      if (!turnstileToken) {
        this.showStatus("Please complete the captcha", "error");
        return;
      }
      try {
        this.showStatus("Posting comment...", "info");
        const submitBtn = document.getElementById("at-comment-submit");
        if (submitBtn) submitBtn.disabled = true;
        const response = await fetch("/api/comment", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            displayName,
            text,
            postUri: this.uri,
            parentUri: this.replyToPost?.uri || null,
            turnstileToken
          })
        });
        const result = await response.json();
        if (!response.ok) {
          throw new Error(result.error || "Failed to post comment");
        }
        this.showStatus("Comment posted! Reloading comments...", "success");
        textarea.value = "";
        nameInput.value = "";
        this.replyToPost = null;
        this.resetTurnstile();
        setTimeout(() => this.loadComments(), 3e3);
      } catch (error) {
        console.error("Post comment error:", error);
        this.showStatus(`Failed to post: ${error.message}`, "error");
        this.resetTurnstile();
        if (this.updateSubmitState) this.updateSubmitState();
      }
    }
    showStatus(message, type) {
      const statusEl = this.container.querySelector(".at-comment-form-status");
      if (statusEl) {
        statusEl.textContent = message;
        statusEl.className = `at-comment-form-status at-comment-status-${type}`;
        setTimeout(() => {
          statusEl.textContent = "";
          statusEl.className = "at-comment-form-status";
        }, 5e3);
      }
    }
    escapeHtml(text) {
      const div = document.createElement("div");
      div.textContent = text;
      return div.innerHTML;
    }
  };
  if (typeof window !== "undefined") {
    window.AtCommentsWidget = AtCommentsWidget;
  }
  var at_comments_default = AtCommentsWidget;
})();
//# sourceMappingURL=at_comments.js.map
