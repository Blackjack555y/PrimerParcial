import React, { useMemo } from 'react';
import { Scenario } from '../types';
import '../styles/GraphVisualization.css';

interface Node {
  id: string;
  label: string;
  x: number;
  y: number;
  recharge: boolean;
}

interface Edge {
  from: string;
  to: string;
  cost: number;
  door?: string | null;
}

interface GraphVisualizationProps {
  scenario: Scenario;
}

export const GraphVisualization: React.FC<GraphVisualizationProps> = ({ scenario }) => {
  const { nodes, edges } = useMemo(() => {
    const nodes: Node[] = scenario.zones.map((zone) => ({
      id: zone.id,
      label: zone.name,
      x: Math.random() * 600 + 50,
      y: Math.random() * 400 + 50,
      recharge: zone.recharge || false,
    }));

    // Posiciones predefinidas basadas en el layout del escenario
    const positionMap: Record<string, [number, number]> = {
      Z1: [150, 100],   // CONTROL
      Z2: [350, 100],   // STORAGE
      Z3: [350, 300],   // WORKSHOP
      Z4: [150, 300],   // GENERATOR_BAY
      Z5: [150, 500],   // COMMAND_DECK
    };

    nodes.forEach((node) => {
      if (positionMap[node.id]) {
        [node.x, node.y] = positionMap[node.id];
      }
    });

    // Eliminar duplicados de edges (mantener solo una dirección)
    const edgeSet = new Set<string>();
    const edges: Edge[] = scenario.corridors
      .filter((corridor) => {
        const key = [
          Math.min(corridor.from, corridor.to),
          Math.max(corridor.from, corridor.to),
        ].join('-');
        if (edgeSet.has(key)) return false;
        edgeSet.add(key);
        return true;
      })
      .map((corridor) => ({
        from: corridor.from,
        to: corridor.to,
        cost: corridor.cost,
        door: corridor.door,
      }));

    return { nodes, edges };
  }, [scenario]);

  const svgWidth = 600;
  const svgHeight = 600;

  return (
    <div className="graph-visualization">
      <h2>Facility Map — Zone Graph</h2>
      <svg
        width={svgWidth}
        height={svgHeight}
        viewBox={`0 0 ${svgWidth} ${svgHeight}`}
        className="graph-svg"
      >
        {/* Dibujar aristas (edges) */}
        <g className="edges">
          {edges.map((edge, idx) => {
            const fromNode = nodes.find((n) => n.id === edge.from)!;
            const toNode = nodes.find((n) => n.id === edge.to)!;

            const midX = (fromNode.x + toNode.x) / 2;
            const midY = (fromNode.y + toNode.y) / 2;

            return (
              <g key={`edge-${idx}`}>
                {/* Línea de conexión */}
                <line
                  x1={fromNode.x}
                  y1={fromNode.y}
                  x2={toNode.x}
                  y2={toNode.y}
                  className={edge.door ? 'edge edge-door' : 'edge'}
                  strokeWidth={edge.door ? 3 : 2}
                  stroke={edge.door ? '#FFD700' : '#999'}
                />
                {/* Etiqueta de costo */}
                <text
                  x={midX}
                  y={midY - 5}
                  className="edge-label"
                  textAnchor="middle"
                >
                  cost: {edge.cost}
                </text>
                {/* Etiqueta de puerta si existe */}
                {edge.door && (
                  <text
                    x={midX}
                    y={midY + 12}
                    className="door-label"
                    textAnchor="middle"
                  >
                    🔒 {edge.door}
                  </text>
                )}
              </g>
            );
          })}
        </g>

        {/* Dibujar nodos (zonas) */}
        <g className="nodes">
          {nodes.map((node) => (
            <g key={node.id}>
              {/* Círculo del nodo */}
              <circle
                cx={node.x}
                cy={node.y}
                r={35}
                className={node.recharge ? 'node node-charger' : 'node'}
                fill={node.recharge ? '#90EE90' : '#87CEEB'}
                stroke="#333"
                strokeWidth={2}
              />
              {/* Icono de cargador */}
              {node.recharge && (
                <text x={node.x} y={node.y + 3} textAnchor="middle" fontSize="16">
                  ⚡
                </text>
              )}
              {/* ID de zona */}
              <text
                x={node.x}
                y={node.y - 8}
                className="node-id"
                textAnchor="middle"
                fontSize="12"
                fontWeight="bold"
              >
                {node.id}
              </text>
              {/* Nombre de zona */}
              <text
                x={node.x}
                y={node.y + 8}
                className="node-label"
                textAnchor="middle"
                fontSize="11"
              >
                {node.label}
              </text>
            </g>
          ))}
        </g>
      </svg>

      {/* Leyenda */}
      <div className="graph-legend">
        <div className="legend-item">
          <div className="legend-box" style={{ backgroundColor: '#87CEEB' }} />
          <span>Regular Zone</span>
        </div>
        <div className="legend-item">
          <div className="legend-box" style={{ backgroundColor: '#90EE90' }} />
          <span>Charger Zone (⚡)</span>
        </div>
        <div className="legend-item">
          <div className="legend-box" style={{ backgroundColor: '#999' }} />
          <span>Open Corridor</span>
        </div>
        <div className="legend-item">
          <div className="legend-box" style={{ backgroundColor: '#FFD700' }} />
          <span>Locked Door (🔒)</span>
        </div>
      </div>
    </div>
  );
};
