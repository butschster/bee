# Shell refinement

Four focused passes prepare the desktop for the next foundation phase.

1. **Window controls.** Minimize is the primary hide action, available from the
   title bar, Start and Alt+F9. Muted tabs identify minimized windows; clicking a
   tab or Alt+Tab restores them, including when every window is minimized.
   Maximize and close have separate visible controls. Collapsed windows remain
   available as a secondary option, with a complete flat bar that can be dragged
   without losing its expanded dimensions.
2. **Input ownership.** Focus and minimize predict input ownership while drawing
   remains committed session state. Correlated acknowledgements settle even
   no-op commands. Clicking the desktop clears focus. Escape cancels a drag;
   resize and application closure release capture safely. Regression scenarios
   send shortcuts and text in the same terminal read.
3. **Appearance and small windows.** Settings remains an independent process.
   Its 14 themes and 11 backgrounds have clickable previews using the same
   wallpaper renderer as the desktop. Wheel and Page Up/Down browse without
   changing preferences. Short windows use compact selection controls. Frame
   and body backgrounds agree across light and dark themes.
4. **Lifecycle and verification.** Protocol tests validate acknowledgement data
   and copied scene ownership. Source and packed acceptance exercises repeated
   presenter replacement, crash recovery, retry exhaustion, independent app
   state, window geometry, input isolation and prompt shutdown. Registry audits
   exclude legacy code, fixtures and test entries from the production package.

Live presenter replacement preserves application producers, window state and
appearance. A full runtime restart still loses workspace state. Local SQLite
migrations and application checkpoint/restore are the next phase, as described
in [WORKSPACE_STATE.md](WORKSPACE_STATE.md). General installation, MCP and agent
drivers remain separate from the desktop.

After this update, exit with Ctrl+Q and run `./run.sh` again: changes include the
stable workspace and session processes, which F12 does not replace.

## Second refinement round

1. Reduced Start to a hierarchical launcher (Tools and Exit), moved window
   actions to title/tab context menus, and added hover selection. Nested levels
   support click/Right to enter and Left/back to return. No instruction legend
   or duplicate menu heading consumes rows.
2. Added the on-demand Process Manager with measured heap, scheduler and queue
   histories, pause, stable row identity, sorting and broker-scoped app closure.
3. Fixed the drag-drop handoff: retain the preview until committed geometry
   arrives. Acceptance checks every synchronized frame during the handoff.
   Contextual restore also restores input ownership.
4. Separated core, shared UI and default apps; added supervisor inspection,
   counter-reset/gap handling, small-window checks and source/pack lifecycle
   coverage. Documented independent package and future self-edit boundaries.

The panel-colored Settings frame is retained: the frame and body share one
surface color, with contrast against the desktop. This avoids mismatched border
bands across light and dark themes.
