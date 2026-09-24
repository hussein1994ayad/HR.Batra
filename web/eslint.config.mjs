import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      // الصفحات تجلب بياناتها داخل useEffect وتضبط حالة التحميل قبل الطلب.
      // هذا نمط مقصود هنا؛ البديل (مكتبة جلب مثل TanStack Query) إعادة هيكلة
      // مستقلة. نبقيه تحذيراً حتى يظهر في المراجعة ولا يوقف الـ CI.
      "react-hooks/set-state-in-effect": "warn",
    },
  },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
]);

export default eslintConfig;
