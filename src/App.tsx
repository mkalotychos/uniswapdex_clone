import { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Layout from "./components/layout/Layout";
import Toaster from "./components/common/Toaster";
import LoadingScreen from "./components/common/LoadingScreen";
import SwapPage from "./pages/SwapPage";
import TestnetHelper from "./pages/TestnetHelper";

export default function App() {
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const timer = setTimeout(() => setLoading(false), 1000);
    return () => clearTimeout(timer);
  }, []);

  if (loading) return <LoadingScreen />;

  return (
    <BrowserRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<SwapPage />} />
          <Route path="/testnet" element={<TestnetHelper />} />
        </Routes>
      </Layout>
      <Toaster />
    </BrowserRouter>
  );
}
