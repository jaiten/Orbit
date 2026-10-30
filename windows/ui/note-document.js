// Safe plain-text document with inline photo anchors. Stored notes stay portable text;
// photo positions use UTF-16 offsets, shared with NSString on iOS.
const OrbitNoteDocument = (() => {
  function read(root) {
    let text = "";
    const photos = [];
    function visit(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        text += node.textContent;
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) return;
      if (node.matches?.("[data-photo-id]")) {
        photos.push({
          id: node.dataset.photoId,
          contentType: "image/jpeg",
          position: String(text.length),
          wrap: node.dataset.wrap || "inline",
        });
        return;
      }
      if (node.nodeName === "BR") {
        text += "\n";
        return;
      }
      const block = ["DIV", "P"].includes(node.nodeName) && node !== root;
      if (block && text && !text.endsWith("\n")) text += "\n";
      for (const child of node.childNodes) visit(child);
    }
    visit(root);
    // Chromium uses a final <div><br></div> as an empty paragraph/caret holder.
    // Its BR is a filler, so Return stores one newline rather than two.
    const last = root.lastChild;
    const emptyParagraph =
      ["DIV", "P"].includes(last?.nodeName) && last.childNodes.length === 1 && last.firstChild.nodeName === "BR";
    if ((emptyParagraph || (root.childNodes.length === 1 && last?.nodeName === "BR")) && text.endsWith("\n"))
      text = text.slice(0, -1);
    return { text, photos };
  }
  function figure(photo) {
    // IDs are validated before they become a local resource URL.
    if (!/^[0-9a-f-]{36}$/.test(photo.id)) return "";
    const wrap = ["left", "right"].includes(photo.wrap) ? photo.wrap : "inline";
    return `<figure contenteditable="false" tabindex="0" data-photo-id="${photo.id}" data-wrap="${wrap}" aria-label="Note photo. Backspace to remove."><img src="orbit://app/photos/${photo.id}.jpg" alt="Note photo" draggable="false" /><figcaption><button type="button" data-photo-action="copy" aria-label="Copy photo">Copy</button><button type="button" data-photo-action="inline" aria-label="Photo on its own line">Inline</button><button type="button" data-photo-action="left" aria-label="Wrap text to the right">Left</button><button type="button" data-photo-action="right" aria-label="Wrap text to the left">Right</button><button type="button" data-photo-action="delete" class="danger" aria-label="Remove photo">Remove</button></figcaption></figure>`;
  }
  function markup(text, photos) {
    text = text.replace(/^([ \t]*)([•◦▪]) /gm, (_, indentation) => {
      const depth = Math.floor(indentation.replace(/\t/g, "    ").length / 4);
      return indentation + (depth === 0 ? "•" : depth === 1 ? "◦" : "▪") + " ";
    });
    let result = "",
      offset = 0;
    [...photos]
      .sort((a, b) => Number(a.position ?? text.length) - Number(b.position ?? text.length))
      .forEach((photo) => {
        const position = Math.max(offset, Math.min(text.length, Number(photo.position ?? text.length) || 0));
        result += esc(text.slice(offset, position)) + figure(photo);
        offset = position;
      });
    return result + esc(text.slice(offset));
  }
  function caret(root) {
    const selection = getSelection();
    if (!selection.rangeCount || !root.contains(selection.anchorNode)) return read(root).text.length;
    const range = selection.getRangeAt(0).cloneRange();
    range.selectNodeContents(root);
    const current = selection.getRangeAt(0);
    range.setEnd(current.startContainer, current.startOffset);
    return read(range.cloneContents()).text.length;
  }
  function select(root, start, end = start) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) =>
        node.parentElement.closest("[data-photo-id]") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    const point = (offset) => {
      for (const node of nodes) {
        const prefix = document.createRange();
        prefix.selectNodeContents(root);
        prefix.setEnd(node, 0);
        const start = read(prefix.cloneContents()).text.length;
        if (offset >= start && offset <= start + node.length) return [node, offset - start];
      }
      return [root, root.childNodes.length];
    };
    const range = document.createRange();
    range.setStart(...point(start));
    range.setEnd(...point(end));
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }
  function bind(root) {
    Object.defineProperty(root, "value", { get: () => read(root).text });
    root.setSelectionRange = (start, end) => select(root, start, end);
    root.addEventListener("keydown", (event) => {
      if (event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return;
      const selectedPhoto = root.querySelector("figure.photo-selected");
      if (selectedPhoto && ["Backspace", "Delete"].includes(event.key)) {
        event.preventDefault();
        removePhoto(selectedPhoto);
        return;
      }
      if (event.key !== "Tab" && event.key !== "Enter") return;
      const value = read(root).text,
        offset = caret(root);
      const start = value.lastIndexOf("\n", offset - 1) + 1;
      const prefix = value.slice(start, offset);
      if (event.key === "Tab") {
        event.preventDefault();
        const selection = getSelection();
        const end = offset + read(selection.getRangeAt(0).cloneContents()).text.length;
        const last = value.indexOf("\n", Math.max(offset, end - 1));
        const stop = last < 0 ? value.length : last;
        let position = start;
        const changes = value
          .slice(start, stop)
          .split("\n")
          .map((line) => {
            const size = event.shiftKey ? line.match(/^( {1,4}|\t)/)?.[0].length || 0 : 0;
            const change = { position, size, text: event.shiftKey ? "" : "    ", line };
            position += line.length + 1;
            return change;
          });
        // Change prefixes individually so indenting a line never replaces its inline photos.
        for (const change of [...changes].reverse()) {
          select(root, change.position, change.position + change.size);
          document.execCommand("insertText", false, change.text);
          const prefix = change.line.match(/^([ \t]*)([•◦▪-]) /);
          if (prefix) {
            const indentation = event.shiftKey ? prefix[1].slice(change.size) : "    " + prefix[1];
            const depth = Math.floor(indentation.replace(/\t/g, "    ").length / 4);
            const marker = depth === 0 ? "•" : depth === 1 ? "◦" : "▪";
            const offset = change.position + indentation.length;
            select(root, offset, offset + 1);
            document.execCommand("insertText", false, marker);
          }
        }
        const shifted = (point) =>
          point +
          changes
            .filter((change) => change.position <= point)
            .reduce((sum, change) => sum + change.text.length - change.size, 0);
        select(root, Math.max(start, shifted(offset)), Math.max(start, shifted(end)));
      } else {
        event.preventDefault();
        const match = prefix.match(/^([ \t]*)([•◦▪-]|\d+\.) /);
        if (match && prefix === match[0]) {
          select(root, start, offset);
          document.execCommand("insertText", false, "");
        } else {
          const marker = match ? (/\d/.test(match[2]) ? `${parseInt(match[2], 10) + 1}.` : match[2]) : "";
          document.execCommand("insertText", false, "\n" + (match ? match[1] + marker + " " : ""));
        }
      }
    });
    root.addEventListener("beforeinput", (event) => {
      if (event.isComposing || event.inputType !== "insertText" || event.data !== " ") return;
      const offset = caret(root),
        value = read(root).text;
      const start = value.lastIndexOf("\n", offset - 1) + 1;
      if (!/^[ \t]*-$/.test(value.slice(start, offset))) return;
      event.preventDefault();
      select(root, offset - 1, offset);
      document.execCommand("insertText", false, "• ");
    });
    root.addEventListener("click", (event) => {
      root.querySelectorAll("figure.photo-selected").forEach((photo) => photo.classList.remove("photo-selected"));
      const photo = event.target.closest("[data-photo-id]");
      if (!photo) return;
      photo.classList.add("photo-selected");
      const action = event.target.closest("[data-photo-action]")?.dataset.photoAction;
      if (action === "copy") void api.copyNotePhoto(photo.dataset.photoId).catch((error) => showNotice(error.message));
      else if (action === "delete") removePhoto(photo);
      else if (action) {
        photo.dataset.wrap = action;
        root.dispatchEvent(new Event("input", { bubbles: true }));
      } else photo.focus();
    });
    root.addEventListener("input", () => {
      notePhotoDraft = read(root).photos;
    });
  }
  function removePhoto(photo) {
    const range = document.createRange();
    range.selectNode(photo);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    photo.closest("[contenteditable=true]").focus();
    document.execCommand("delete");
  }
  return { read, markup, bind, figure };
})();
