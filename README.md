# @celia-sh/react-native-pretty-toast

> **CELIA self-use fork:** This package is maintained for CELIA's own internal
> applications. It is a fork of the upstream project and is not intended as a
> general-purpose public distribution or a replacement for upstream support.

https://github.com/user-attachments/assets/b59a22b7-913d-4bc3-9629-5549de5e28d4

A toast library that actually uses the hardware cutout. The pill morphs out of the Dynamic Island on iPhone and out of the camera cutout on Android, expands to fit your content, and collapses back in — with sensible slide-in fallbacks on devices without a cutout.

- **Cutout-anchored toast on both platforms** — Dynamic Island on iPhones, the iPhone Duo's cover-display camera, and `DisplayCutout` hole-punch on Android, detected automatically from system insets
- **Backdrop-aware outline** — samples the content underneath and flips the stroke between accent and neutral so the pill stays legible on any background
- **One API, three platforms** — iOS, Android, and Web share the same `toast.show()` call
- **Sonner-style ergonomics** — `toast.promise()`, `toast.update()`, and `success` / `error` / `info` / `warning` / `loading` shorthands
- **Works outside React** — call `toast.show()` from redux middleware, fetch interceptors, or anywhere else; no `useContext` required
- **Interactive out of the box** — swipe-up to dismiss, tappable pill, and a trailing action button for undo/retry
- **Production-minded** — FIFO queue with `maxQueue` cap, `{ force: true }` for critical interrupts, full lifecycle hooks (`onShow`, `onHide`, `onAutoDismiss`)
- **Accessible by default** — screen-reader announcements on native (`AccessibilityInfo`) and web (`aria-live`), overridable per-toast
- **Fabric / New Architecture only**

## Installation

```sh
npm install @celia-sh/react-native-pretty-toast
```

### iOS Setup

#### Required: Info.plist

Set this key in your app's `Info.plist`:

```xml
<key>UIViewControllerBasedStatusBarAppearance</key>
<true/>
```

On iPhone the toast hides the status bar through its overlay window's view
controller while the pill is out, and hides that window between toasts so your
own screens keep control of the status bar. On iPadOS the toast leaves the
status bar visible. Apps linked against the iOS 27 SDK need the key anyway: iOS
27 no longer applies `UIApplication`'s app-wide status bar API to them.

**Expo users:** set it under `ios.infoPlist` in your app config, and drive the
status bar per screen (for example native-stack `statusBarHidden` and
`statusBarStyle`) instead of `expo-status-bar` or React Native's `StatusBar`,
which expect the key to be `false`.

#### Requirements

- iOS 15.1+ (Dynamic Island features require iPhone 14 Pro or later; older devices get a slide-in toast)
- React Native 0.76+ (New Architecture / Fabric)

## Usage

Wrap your app with `ToastProvider` once at the root:

```tsx
import { ToastProvider } from '@celia-sh/react-native-pretty-toast';

export default function App() {
  return (
    <ToastProvider>
      <HomeScreen />
    </ToastProvider>
  );
}
```

You can trigger toasts two ways — pick whichever fits your use case:

### 1. Imperative API (call from anywhere)

Import `toast` directly. Works in non-component code: API error handlers, redux middleware, utility modules, etc.

```tsx
import { toast } from '@celia-sh/react-native-pretty-toast';

toast.show({
  icon: 'checkmark.seal.fill',
  title: 'Transaction Success!',
  message: 'Your payment has been processed',
});
```

### 2. `useToast` hook (inside components)

```tsx
import { useToast } from '@celia-sh/react-native-pretty-toast';

function HomeScreen() {
  const toast = useToast();

  return (
    <Button
      title="Show Toast"
      onPress={() =>
        toast.show({
          icon: 'checkmark.seal.fill',
          title: 'Transaction Success!',
          message: 'Your payment has been processed',
          duration: 3000,
        })
      }
    />
  );
}
```

Both share the same queue and state — calls from either entry point behave identically.

## API

### `<ToastProvider>`

Mount once at the root of your app.

| Prop               | Type                    | Default   | Description                                                                                                                                                   |
| ------------------ | ----------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `children`         | `ReactNode`             | —         | Your app tree.                                                                                                                                                |
| `useDynamicIsland` | `boolean`               | `true`    | When `false`, always use the slide-in variant even on Dynamic Island devices.                                                                                 |
| `defaultConfig`    | `ToastProviderDefaults` | —         | Defaults merged into every toast. Per-toast values always win. Excludes content fields (`id`, `title`, `message`, `icon`, `iconSource`, `onPress`, `action`). |
| `maxQueue`         | `number`                | unlimited | Max queue depth excluding the visible toast. When exceeded, the oldest queued toast is dropped. `0` disables queueing.                                        |

```tsx
<ToastProvider
  useDynamicIsland
  maxQueue={3}
  defaultConfig={{ duration: 4000, enableSwipeDismiss: true }}
>
  <App />
</ToastProvider>
```

### `toast.show(config, options?)`

Shows a toast. Returns the toast's `id` so you can `update` or `dismiss` it later.

```ts
const id = toast.show({
  icon: 'checkmark.seal.fill',
  title: 'Saved',
  message: 'Changes written to disk',
});
```

#### `ToastConfig`

| Field                       | Type                  | Default           | Description                                                                                                                                                                    |
| --------------------------- | --------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `id`                        | `string`              | auto              | Stable identifier. Auto-generated if omitted.                                                                                                                                  |
| `icon`                      | `SFSymbolName`        | —                 | SF Symbol name (e.g. `'checkmark.seal.fill'`). Ignored when `iconSource` is set. On Android it's mapped to a bundled drawable via substring match; on web, to a unicode glyph. |
| `iconSource`                | `ImageSourcePropType` | —                 | Custom image — `require(...)`, remote URL, or file URI. When set, overrides `icon`.                                                                                            |
| `title`                     | `string`              | —                 | Bold title line.                                                                                                                                                               |
| `message`                   | `string`              | —                 | Subtitle line. Pill height expands to fit.                                                                                                                                     |
| `duration`                  | `number`              | `3000`            | Auto-dismiss delay in ms. Ignored when `autoDismiss` is `false` or `duration <= 0`.                                                                                            |
| `autoDismiss`               | `boolean`             | `true`            | If `false`, toast stays until explicitly dismissed.                                                                                                                            |
| `enableSwipeDismiss`        | `boolean`             | `true`            | Swipe-up to dismiss.                                                                                                                                                           |
| `accentColor`               | `ColorValue`          | derived           | Overrides the color derived from the icon. Drives the icon tint and pill accent stroke.                                                                                        |
| `strokeColor`               | `ColorValue`          | dynamic           | Fixed stroke color. Pass `rgba(...)` if you want transparency.                                                                                                                 |
| `disableBackdropSampling`   | `boolean`             | `false`           | Skip the backdrop luminance sampler that flips the outline between accent and neutral over varying backdrops.                                                                  |
| `action`                    | `ToastAction`         | —                 | Trailing button (`{ label, onPress }`). Tapping dismisses the toast.                                                                                                           |
| `accessibilityAnnouncement` | `string`              | `title + message` | Custom screen-reader announcement. Empty string disables the announcement.                                                                                                     |
| `onPress`                   | `() => void`          | —                 | Called when the user taps the pill (not the action). Dismisses the toast after.                                                                                                |
| `onShow`                    | `() => void`          | —                 | Fires when the toast begins presenting.                                                                                                                                        |
| `onHide`                    | `() => void`          | —                 | Fires when the toast finishes dismissing, for any reason.                                                                                                                      |
| `onAutoDismiss`             | `() => void`          | —                 | Fires only when dismissal was caused by the duration timer. Fires before `onHide`.                                                                                             |

#### `ShowOptions`

| Field   | Type      | Description                                                           |
| ------- | --------- | --------------------------------------------------------------------- |
| `force` | `boolean` | Preempt the currently visible toast and present this one immediately. |

```tsx
toast.show({ title: 'Session expired' }, { force: true });
```

### Variant shorthands

Each returns a toast `id`, accepts the same `ShowOptions`, and pre-fills the icon.

```ts
toast.success(title, config?, options?);
toast.error(title, config?, options?);
toast.info(title, config?, options?);
toast.warning(title, config?, options?);
toast.loading(title, config?, options?); // autoDismiss defaults to false
```

```tsx
toast.success('Saved');
toast.error('Upload failed', {
  message: 'Check your connection',
  duration: 5000,
});
toast.loading('Uploading…');
```

### `toast.update(id, partial)`

Mutate an existing toast in place. Live toasts patch without re-running the enter animation; queued toasts are patched before presentation.

```tsx
const id = toast.loading('Uploading…');
// later
toast.update(id, {
  title: 'Done',
  icon: 'checkmark.circle.fill',
  autoDismiss: true,
});
```

### `toast.promise(promise, messages)`

Tie a toast's lifecycle to a promise. Shows a loading toast, morphs into success or error when the promise settles. Returns the original promise so `await` chains are preserved.

```tsx
await toast.promise(api.save(data), {
  loading: 'Saving…',
  success: (result) => `Saved ${result.name}`,
  error: (e) => `Failed: ${(e as Error).message}`,
});
```

Each `messages` field accepts either a plain string (rendered as the title) or a full `ToastConfig` (minus `id`). `success` and `error` additionally accept a function of the resolved value / error.

### `toast.dismiss(id?)`

Dismiss the visible toast, or a specific queued toast by id.

### `toast.dismissAll()`

Dismiss the visible toast and clear the queue.

### Queue behavior

Multiple `toast.show()` calls are queued. Each toast is displayed after the previous one is dismissed. Use `maxQueue` on the provider to cap depth, or `{ force: true }` to preempt.

## SF Symbol Icons

The `icon` prop accepts any [SF Symbol](https://developer.apple.com/sf-symbols/) name. Browse the full catalog in Apple's SF Symbols app or online at **[sfsymbols.com](https://sfsymbols.com)**. Icon tint color is automatically determined:

| Symbol contains | Color  |
| --------------- | ------ |
| `checkmark`     | Green  |
| `xmark`         | Red    |
| `exclamation`   | Orange |
| `info`          | Blue   |
| `heart`         | Pink   |
| `arrow`         | Blue   |
| Other           | Gray   |

Override with `accentColor` for any custom tint.

## Examples

A runnable demo lives in [`example/`](./example) — an Expo app that exercises every variant, lifecycle hook, and custom-icon path. The web build is also deployed at **[blazejkustra.github.io/react-native-pretty-toast](https://blazejkustra.github.io/react-native-pretty-toast)**.

```sh
yarn install
yarn example ios      # or: yarn example android / yarn example web
```

`yarn example start` launches the Metro dev server if you already have a dev client installed. First run on a simulator/device uses `ios` / `android` to produce a native build.

```tsx
// Persistent with an action
toast.show({
  icon: 'trash.fill',
  title: 'Message deleted',
  autoDismiss: false,
  action: {
    label: 'Undo',
    onPress: () => restoreMessage(),
  },
});

// Custom icon from a remote URL
toast.show({
  iconSource: { uri: 'https://example.com/avatar.png' },
  title: 'Alice sent you a message',
});

// Lifecycle hooks
toast.show({
  title: 'Connected',
  onShow: () => analytics.track('toast_shown'),
  onAutoDismiss: () => analytics.track('toast_timed_out'),
  onHide: () => cleanup(),
});

// Preempt the current toast
toast.show({ title: 'Session expired' }, { force: true });
```

## License

MIT

<p align="center">
  <img src="./assets/logo.png" alt="react-native-pretty-toast" width="160" />
</p>
