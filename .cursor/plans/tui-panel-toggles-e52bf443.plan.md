<!-- e52bf443-991c-4c4c-a83f-7f29f5c810dc 28ce1225-d8f6-425b-9510-72798f9eb6fe -->
# TUI Panel Toggles Implementation - Phased Approach

## Overview

Transform the TUI from a single-page display to a toggle-based interface similar to btop, where users can show/hide panels dynamically using keyboard shortcuts. Implementation broken into 4 phases for incremental delivery and testing.

## Phase 1: Core Toggle Foundation

**Goal**: Basic panel toggling with number keys and Tab cycling. All existing panels work with toggle system.

**Deliverables**:

- Panel toggle system working (show/hide panels with 1-3 keys)
- Tab key cycles through visible panels (selection only, doesn't hide)
- Selected panel title underlined
- Basic persistence (save/load toggle state)
- Default config for panel visibility
- All existing panels (Status, Balances, Activity) work with toggle system

**Files to Create/Modify**:

- `Sources/SmartVestorCore/PanelToggleManager.swift` - Toggle state with persistence
- `Sources/SmartVestorCore/EnhancedTUIRenderer.swift` - Integrate toggle manager, show/hide panels
- `Sources/SmartVestorCore/LayoutManager.swift` - Dynamic layout for visible panels only
- `Sources/SmartVestor/WorkingCLI.swift` - Keyboard shortcuts 1-3 and Tab
- Update existing panel renderers to support selection (underlined title)
- `config/tui_panel_config.json` - Default panel visibility config

**Testing**: Manual testing of toggle and Tab cycling

---

## Phase 2: Scroll, Sort, and New Panels

**Goal**: Add scrollable lists, price sorting, and new Price panel.

**Deliverables**:

- Scrollable lists in panels (j/k for line, Ctrl+J/K for page)
- Debounced key handling
- Price panel with sorting (stable sort)
- Price panel renderer
- Context-sensitive command bar (static dictionary)
- Min-height enforcement for panels

**Files to Create/Modify**:

- `Sources/SmartVestorCore/PanelScrollState.swift` - Scroll management with page support
- `Sources/SmartVestorCore/PriceSortManager.swift` - Stable sorting
- `Sources/SmartVestorCore/KeyDebouncer.swift` - Key debouncing
- `Sources/SmartVestorCore/PricePanelRenderer.swift` - Price panel
- `Sources/SmartVestorCore/CommandBarRenderer.swift` - Context-sensitive commands
- `Sources/SmartVestorCore/LayoutManager.swift` - Add min-height enforcement
- `Sources/SmartVestorCore/LayoutManager.swift` - Add .price to PanelType enum
- `Sources/SmartVestor/WorkingCLI.swift` - Keyboard shortcuts j/k, Ctrl+J/K, s
- `Sources/SmartVestorCore/EnhancedTUIRenderer.swift` - Integrate scroll, sort, price panel

**Testing**: Unit tests for ScrollState and SortManager, manual testing of scrolling and sorting

---

## Phase 3: Swap Panel and Execution

**Goal**: Add swap panel with execution capability, including error handling and rollback.

**Deliverables**:

- Swap panel with scrollable list
- Swap execution with confirmation
- Error rollback and retry logic
- Rate limiting on TUI updates
- Terminal resize handling

**Files to Create/Modify**:

- `Sources/SmartVestorCore/TUIModels.swift` - Add swapEvaluations to TUIData
- `Sources/SmartVestorCore/SwapPanelRenderer.swift` - Swap panel renderer
- `Sources/SmartVestorCore/SwapExecutionManager.swift` - Execution with rollback/retry
- `Sources/SmartVestorCore/UpdateRateLimiter.swift` - Rate limiting
- `Sources/SmartVestorCore/TerminalResizeHandler.swift` - Resize handling
- `Sources/SmartVestorCore/LayoutManager.swift` - Add .swap to PanelType enum
- `Sources/SmartVestorCore/ContinuousRunner.swift` - Include swap evaluations in TUI updates
- `Sources/SmartVestor/WorkingCLI.swift` - Keyboard shortcut e for execution
- `Sources/SmartVestorCore/EnhancedTUIRenderer.swift` - Integrate swap panel and execution

**Testing**: Unit tests for SwapExecutionManager, manual testing of swap execution and error scenarios

---

## Phase 4: Polish, CLI, and Accessibility

**Goal**: Complete the implementation with CLI tool, accessibility, testing, and all refinements.

**Deliverables**:

- RenderCoordinator actor for thread safety
- FrameBuffer for atomic output
- CLI tui-data command with TSV/CSV output
- CLI authentication
- Basic accessibility features
- Complete help screen (including e key)
- Unit tests for all managers
- Remove unimplemented features from docs

**Files to Create/Modify**:

- `Sources/SmartVestorCore/RenderCoordinator.swift` - Actor-based coordination
- `Sources/SmartVestorCore/FrameBuffer.swift` - Atomic output buffer
- `Sources/SmartVestorCore/AccessibilityManager.swift` - Accessibility support
- `Sources/SmartVestorCore/CLIAuthentication.swift` - CLI auth
- `Sources/SmartVestorCore/CommandBarProtocol.swift` - Command protocol
- `Sources/SmartVestor/WorkingCLI.swift` - TUIDataCommand with TSV/CSV
- `Sources/SmartVestor/WorkingCLI.swift` - Complete help screen
- `Sources/SmartVestorCore/EnhancedTUIRenderer.swift` - Integrate all Phase 4 components
- Update all panel renderers to support accessibility mode
- `Tests/SmartVestorTests/PanelToggleManagerTests.swift`
- `Tests/SmartVestorTests/PanelScrollStateTests.swift`
- `Tests/SmartVestorTests/PriceSortManagerTests.swift`
- `Tests/SmartVestorTests/SwapExecutionManagerTests.swift`

**Testing**: Comprehensive unit tests, integration tests, accessibility testing

---

## Implementation Order Summary

### Phase 1 (Foundation)

1. Create PanelToggleManager with persistence
2. Update LayoutManager for dynamic layouts
3. Add selection support to existing panel renderers
4. Update EnhancedTUIRenderer for toggle integration
5. Add keyboard shortcuts (1-3, Tab) in WorkingCLI
6. Create default panel config file

### Phase 2 (Scrolling & New Panels)

1. Create PanelScrollState with page support
2. Create PriceSortManager
3. Create KeyDebouncer
4. Create PricePanelRenderer
5. Update CommandBarRenderer for context-sensitive commands
6. Update LayoutManager with min-height and .price enum
7. Integrate scrolling and price panel into renderer
8. Add keyboard shortcuts (j/k, Ctrl+J/K, s)

### Phase 3 (Swap & Execution)

1. Add swapEvaluations to TUIData model
2. Create SwapPanelRenderer
3. Create SwapExecutionManager with rollback/retry
4. Create UpdateRateLimiter
5. Create TerminalResizeHandler
6. Update ContinuousRunner to include swap data
7. Update LayoutManager with .swap enum
8. Integrate swap panel and execution
9. Add keyboard shortcut (e)

### Phase 4 (Polish)

1. Create RenderCoordinator actor
2. Create FrameBuffer
3. Create AccessibilityManager
4. Create CLIAuthentication
5. Create CommandBarProtocol
6. Create TUIDataCommand CLI
7. Complete help screen
8. Update all renderers for accessibility
9. Create unit tests for all managers
10. Final integration and cleanup

---

## Key Decisions by Phase

**Phase 1**: Keep it simple - basic toggle works, existing panels functional
**Phase 2**: Add complexity gradually - scrolling and new panels
**Phase 3**: Add most complex feature - swap execution with error handling
**Phase 4**: Polish and production readiness - performance, accessibility, testing

---

## Success Criteria

**Phase 1 Complete**: User can toggle panels 1-3, Tab cycles selection, state persists
**Phase 2 Complete**: User can scroll panels, sort prices, see price panel
**Phase 3 Complete**: User can see swap panel, execute swaps with error handling
**Phase 4 Complete**: Production-ready with tests, accessibility, CLI tool

---

## Future Enhancements (Post-Phase 4)

- Fuzzy search in panels
- Panel docking/reordering
- Reactive streams
- Panel snapshots
- AI-assisted suggestions
- Dynamic themes
- Multi-panel selection
- ASCII charts
- Hot-reload config
- Undo stack
- Voice commands
- Gamification