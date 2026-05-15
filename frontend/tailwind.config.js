/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        dark: {
          900: '#0a0b0f',
          800: '#13141a',
          700: '#1e1f26',
        },
        primary: {
          500: '#6366f1', // indigo
          400: '#818cf8',
        },
        accent: {
          500: '#06b6d4', // cyan
          400: '#22d3ee',
        }
      }
    },
  },
  plugins: [],
}
