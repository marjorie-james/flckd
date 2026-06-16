import "@testing-library/jest-dom";

// jsdom in this environment ships a non-functional localStorage stub (its methods
// are missing), which would make every storage access look "unavailable". Install
// a small Map-backed Storage so on-device persistence (localePreference) is
// exercised for real; tests that simulate a blocked store spy on these methods.
function installMemoryStorage() {
  const store = new Map<string, string>();
  const storage = {
    getItem: (key: string) => (store.has(key) ? store.get(key)! : null),
    setItem: (key: string, value: string) => {
      store.set(key, String(value));
    },
    removeItem: (key: string) => {
      store.delete(key);
    },
    clear: () => {
      store.clear();
    },
    key: (index: number) => Array.from(store.keys())[index] ?? null,
    get length() {
      return store.size;
    },
  };
  Object.defineProperty(window, "localStorage", {
    value: storage,
    configurable: true,
    writable: true,
  });
}

installMemoryStorage();
