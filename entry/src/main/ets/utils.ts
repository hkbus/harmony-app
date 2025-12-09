type CoordinatePoint = {
  latitude: number,
  longitude: number,
};

const convertToRadians = (point: CoordinatePoint): CoordinatePoint => {
  // latitude and longitude are degree values
  // there are 360 degrees in a circle and 2 * Math.PI radians in a circle
  // 360 / (2 * Math.PI) = 57.29577951308232
  // 1 radian = 57.29577951308232 degrees
  // Divide degrees by this number to get the number of radians
  const DEGREE_DIVIDER = 57.29577951308232;

  return {
    latitude: point.latitude / DEGREE_DIVIDER,
    longitude: point.longitude / DEGREE_DIVIDER,
  };
};

const getDistance = (
  from: CoordinatePoint,
  to: CoordinatePoint,
  precision = 2,
  radius: number = 6378000.0, // in meter
): number => {
  // convert coordinate point units from degrees to radians
  const point1: CoordinatePoint = convertToRadians(from);
  const point2: CoordinatePoint = convertToRadians(to);

  // measure the distance between the two points in radians
  const result: number = Math.acos(
    (Math.sin(point1.latitude) * Math.sin(point2.latitude))
      + (Math.cos(point1.latitude) * Math.cos(point2.latitude) * Math.cos(point1.longitude - point2.longitude)),
  );

  // convert the distance in radians to the target unit of measurement
  const distance = radius * result;

  // round the distance to the desired precision
  return parseFloat(distance.toFixed(precision));
};

export default getDistance;