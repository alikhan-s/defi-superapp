import React from 'react';
import { motion } from 'framer-motion';

interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

export const Spinner: React.FC<SpinnerProps> = ({ size = 'md', className = '' }) => {
  const sizeMap = {
    sm: 'w-4 h-4 border-2',
    md: 'w-6 h-6 border-2',
    lg: 'w-10 h-10 border-4',
  };

  return (
    <div className={`relative flex items-center justify-center ${className}`}>
      <motion.div
        className={`rounded-full border-t-indigo-500 border-r-cyan-500 border-b-transparent border-l-transparent ${sizeMap[size]}`}
        animate={{ rotate: 360 }}
        transition={{ duration: 1, repeat: Infinity, ease: "linear" }}
      />
      <motion.div
        className={`absolute rounded-full border-t-transparent border-r-transparent border-b-indigo-400 border-l-cyan-400 opacity-50 ${sizeMap[size]}`}
        animate={{ rotate: -360 }}
        transition={{ duration: 1.5, repeat: Infinity, ease: "linear" }}
      />
    </div>
  );
};
