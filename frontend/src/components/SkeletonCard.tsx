import React from 'react';
import { motion } from 'framer-motion';

interface SkeletonCardProps {
  className?: string;
}

export const SkeletonCard: React.FC<SkeletonCardProps> = ({ className = '' }) => {
  return (
    <div className={`relative overflow-hidden rounded-2xl bg-[#13141a] p-6 border border-white/5 shadow-2xl ${className}`}>
      {/* Skeleton Shimmer Effect */}
      <motion.div
        className="absolute inset-0 z-10 w-full h-full bg-gradient-to-r from-transparent via-white/5 to-transparent skew-x-[-20deg]"
        initial={{ x: '-150%' }}
        animate={{ x: '150%' }}
        transition={{
          repeat: Infinity,
          duration: 1.5,
          ease: 'linear',
        }}
      />
      
      <div className="relative z-0">
        {/* Header Skeleton */}
        <div className="flex items-center space-x-4 mb-6">
          <div className="w-12 h-12 rounded-full bg-white/10" />
          <div className="space-y-2">
            <div className="w-32 h-4 rounded-md bg-white/10" />
            <div className="w-24 h-3 rounded-md bg-white/5" />
          </div>
        </div>
        
        {/* Body Skeleton */}
        <div className="space-y-4">
          <div className="w-full h-12 rounded-xl bg-white/5" />
          <div className="w-full h-12 rounded-xl bg-white/5" />
          <div className="w-3/4 h-12 rounded-xl bg-white/5" />
        </div>
        
        {/* Footer Skeleton */}
        <div className="mt-8 pt-4 border-t border-white/5 flex justify-between items-center">
          <div className="w-20 h-4 rounded-md bg-white/5" />
          <div className="w-28 h-8 rounded-lg bg-white/10" />
        </div>
      </div>
    </div>
  );
};
