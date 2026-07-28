import type { GpsContact, MapView } from '../HelmConsole';

type ContactIndicatorProps = {
  contact: GpsContact;
  heading: number;
  mapView: MapView;
  shipX: number;
  shipY: number;
  shipOffsetX: number;
  shipOffsetY: number;
};

export const ContactIndicator = ({
  contact,
  heading,
  mapView,
  shipX,
  shipY,
  shipOffsetX,
  shipOffsetY,
}: ContactIndicatorProps) => {
  const contactX = contact.x + contact.offsetX;
  const contactY = contact.y + contact.offsetY;
  const normalizedX = (contactX - mapView.minX + 0.5) / mapView.sizeX;
  const normalizedY =
    1 - (contactY - mapView.minY + 0.5) / mapView.sizeY;
  const onScreen =
    normalizedX >= 0 &&
    normalizedX <= 1 &&
    normalizedY >= 0 &&
    normalizedY <= 1;
  const relativeBearing = (contact.bearing - heading + 360) % 360;

  if (onScreen) {
    return (
      <div className="HelmConsole__contact-overlay">
        <div
          className="HelmConsole__contact-reticle"
          style={{
            left: `${normalizedX * 100}%`,
            top: `${normalizedY * 100}%`,
          }}
        >
          <span className="HelmConsole__contact-reticle-ring" />
          <span className="HelmConsole__contact-label">
            {contact.tags.join(', ')}
          </span>
        </div>
      </div>
    );
  }

  const dx = contactX - (shipX + shipOffsetX);
  const screenDy = -(contactY - (shipY + shipOffsetY));
  const scale = Math.min(
    Math.abs(dx) > 0.001 ? 45 / Math.abs(dx) : Infinity,
    Math.abs(screenDy) > 0.001 ? 42 / Math.abs(screenDy) : Infinity,
  );
  const left = 50 + dx * scale;
  const top = 50 + screenDy * scale;
  const arrowRotation = (Math.atan2(dx, -screenDy) * 180) / Math.PI;

  return (
    <div className="HelmConsole__contact-overlay">
      <div
        className="HelmConsole__contact-arrow"
        style={{ left: `${left}%`, top: `${top}%` }}
      >
        <span
          className="HelmConsole__contact-arrow-glyph"
          style={{ transform: `rotate(${arrowRotation}deg)` }}
        >
          ▲
        </span>
        <span className="HelmConsole__contact-label">
          {contact.tags.join(', ')} · REL {Math.round(relativeBearing)}° ·{' '}
          {contact.distance} tiles
        </span>
      </div>
    </div>
  );
};
