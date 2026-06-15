import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import "./i18n";
import { PlanRoutePage } from "./pages/PlanRoutePage";
import "./App.css";

const queryClient = new QueryClient({
  defaultOptions: { queries: { refetchOnWindowFocus: false } },
});

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <PlanRoutePage />
    </QueryClientProvider>
  );
}
