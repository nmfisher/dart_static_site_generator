/**
 * AT Protocol Comments Widget
 * Fetches and renders comments from any AT Protocol AppView
 */
class AtComments {
  constructor(containerId, uri, appViewUrl) {
    this.container = document.getElementById(containerId);
    this.uri = uri;
    this.appViewUrl = appViewUrl || 'https://public.api.bsky.app';
    this.endpoint = `${this.appViewUrl}/xrpc/app.bsky.feed.getPostThread`;
  }

  async load() {
    if (!this.container || !this.uri) {
      console.warn('AtComments: Missing container or URI');
      return;
    }

    try {
      const url = `${this.endpoint}?uri=${encodeURIComponent(this.uri)}&depth=10`;
      const response = await fetch(url);

      if (!response.ok) {
        throw new Error(`Failed to fetch comments: ${response.status}`);
      }

      const data = await response.json();

      // Skip the root post (anchor) and render only replies
      if (data.thread && data.thread.replies && data.thread.replies.length > 0) {
        this.container.innerHTML = '';
        this.renderReplies(data.thread.replies, this.container);
      } else {
        this.renderEmptyState();
      }
    } catch (error) {
      console.error('AtComments: Error loading comments', error);
      this.renderError();
    }
  }

  renderReplies(replies, container, depth = 0) {
    const maxDepth = 5;

    for (const reply of replies) {
      if (!reply.post) continue;

      const comment = this.createCommentElement(reply.post, depth);
      container.appendChild(comment);

      // Render nested replies
      if (reply.replies && reply.replies.length > 0 && depth < maxDepth) {
        const nestedContainer = document.createElement('div');
        nestedContainer.className = 'at-comment-replies';
        this.renderReplies(reply.replies, nestedContainer, depth + 1);
        comment.appendChild(nestedContainer);
      }
    }
  }

  createCommentElement(post, depth) {
    const author = post.author;
    const record = post.record;
    const createdAt = new Date(record.createdAt);

    const comment = document.createElement('div');
    comment.className = `at-comment at-comment-depth-${depth}`;

    const postRkey = post.uri.split('/').pop();

    comment.innerHTML = `
      <div class="at-comment-header">
        <a href="https://bsky.app/profile/${author.handle}"
           target="_blank"
           rel="noopener noreferrer"
           class="at-comment-author">
          ${author.avatar ? `<img src="${author.avatar}" alt="" class="at-comment-avatar">` : ''}
          <span class="at-comment-displayname">${this.escapeHtml(author.displayName || author.handle)}</span>
          <span class="at-comment-handle">@${author.handle}</span>
        </a>
        <time datetime="${createdAt.toISOString()}" class="at-comment-time">
          ${this.formatRelativeTime(createdAt)}
        </time>
      </div>
      <div class="at-comment-content">
        ${this.escapeHtml(record.text)}
      </div>
      <div class="at-comment-actions">
        <a href="https://bsky.app/profile/${author.handle}/post/${postRkey}"
           target="_blank"
           rel="noopener noreferrer"
           class="at-comment-reply-link">
          Reply on Bluesky
        </a>
      </div>
    `;

    return comment;
  }

  renderEmptyState() {
    const parts = this.uri.split('/');
    const postRkey = parts.pop();
    const did = parts[2];

    this.container.innerHTML = `
      <div class="at-comments-empty">
        <p>No comments yet. Be the first to comment!</p>
        <a href="https://bsky.app/profile/${did}/post/${postRkey}"
           target="_blank"
           rel="noopener noreferrer"
           class="at-comment-cta">
          Comment on Bluesky
        </a>
      </div>
    `;
  }

  renderError() {
    this.container.innerHTML = `
      <div class="at-comments-error">
        <p>Unable to load comments. Please try again later.</p>
      </div>
    `;
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  formatRelativeTime(date) {
    const now = new Date();
    const diffMs = now - date;
    const diffSecs = Math.floor(diffMs / 1000);
    const diffMins = Math.floor(diffSecs / 60);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 7) {
      return date.toLocaleDateString();
    } else if (diffDays > 0) {
      return `${diffDays}d ago`;
    } else if (diffHours > 0) {
      return `${diffHours}h ago`;
    } else if (diffMins > 0) {
      return `${diffMins}m ago`;
    } else {
      return 'just now';
    }
  }
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
  module.exports = AtComments;
}
