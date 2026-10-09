import { BrowserRouter, Route, Routes } from "react-router-dom"
import { AppLayout } from "./components/AppLayout"
import { AuthProvider } from "./context/AuthContext"
import { AboutPage } from "./pages/AboutPage"
import { EditWorkshopPage } from "./pages/EditWorkshopPage"
import { HomePage } from "./pages/HomePage"
import { NewWorkshopPage } from "./pages/NewWorkshopPage"
import { NotFoundPage } from "./pages/NotFoundPage"
import { WorkshopDetailPage } from "./pages/WorkshopDetailPage"
import { WorkshopsPage } from "./pages/WorkshopsPage"

export const App = () => (
  <AuthProvider>
    <BrowserRouter>
      <Routes>
        <Route element={<AppLayout />}>
          <Route index element={<HomePage />} />
          <Route path="workshops" element={<WorkshopsPage />} />
          <Route path="workshops/new" element={<NewWorkshopPage />} />
          <Route path="workshops/:id" element={<WorkshopDetailPage />} />
          <Route path="workshops/:id/edit" element={<EditWorkshopPage />} />
          <Route path="about" element={<AboutPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </AuthProvider>
)
