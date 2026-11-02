import React from 'react';
import { ChevronRight } from 'lucide-react';

export function Breadcrumbs({ items = [] }) {
  if (!items || items.length === 0) return null;

  return (
    <nav className="tm-breadcrumbs" aria-label="Fil d'Ariane">
      <ol className="tm-breadcrumbs-list">
        {items.map((item, idx) => {
          const isLast = idx === items.length - 1;
          return (
            <li key={idx} className={`tm-breadcrumbs-item ${isLast ? 'active' : ''}`}>
              {idx > 0 && <ChevronRight size={13} className="tm-breadcrumbs-separator" />}
              {item.onClick && !isLast ? (
                <button
                  type="button"
                  className="tm-breadcrumbs-link"
                  onClick={item.onClick}
                >
                  {item.icon && <span className="tm-breadcrumbs-icon">{item.icon}</span>}
                  <span>{item.label}</span>
                </button>
              ) : (
                <span className="tm-breadcrumbs-current">
                  {item.icon && <span className="tm-breadcrumbs-icon">{item.icon}</span>}
                  <span>{item.label}</span>
                </span>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
