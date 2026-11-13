use bevy::prelude::*;

const EPSILON: f32 = 1e-5;
const SKIN: f32 = 1e-4;

#[derive(Clone, Copy, Debug)]
pub struct Aabb {
    pub min: Vec3,
    pub max: Vec3,
}

impl Aabb {
    pub fn from_center_size(center: Vec3, size: Vec3) -> Self {
        Self {
            min: center - size * 0.5,
            max: center + size * 0.5,
        }
    }

    pub fn overlaps_circle(self, point: Vec2, radius: f32) -> bool {
        let nearest = point.clamp(self.min.xz(), self.max.xz());
        point.distance_squared(nearest) < radius * radius
    }
}

#[derive(Resource)]
pub struct CollisionMap {
    pub half_size: f32,
    pub movement: Vec<Aabb>,
    pub camera: Vec<Aabb>,
}

#[derive(Clone, Copy)]
struct Hit {
    time: f32,
    normal: Vec2,
}

fn offer_hit(best: &mut Option<Hit>, time: f32, normal: Vec2, delta: Vec2) {
    if (0.0..=1.0).contains(&time)
        && delta.dot(normal) < -EPSILON
        && best.is_none_or(|hit| time < hit.time)
    {
        *best = Some(Hit { time, normal });
    }
}

fn sweep_circle(start: Vec2, delta: Vec2, radius: f32, obstacle: Aabb) -> Option<Hit> {
    let min = obstacle.min.xz();
    let max = obstacle.max.xz();
    let mut best = None;
    // The Minkowski boundary consists of four faces and four circular corners.
    for (axis, other) in [(0, 1), (1, 0)] {
        if delta[axis].abs() <= EPSILON {
            continue;
        }
        for (face, sign) in [(min[axis] - radius, -1.0), (max[axis] + radius, 1.0)] {
            let time = (face - start[axis]) / delta[axis];
            let lateral = start[other] + delta[other] * time;
            if lateral >= min[other] && lateral <= max[other] {
                let mut normal = Vec2::ZERO;
                normal[axis] = sign;
                offer_hit(&mut best, time, normal, delta);
            }
        }
    }
    let a = delta.length_squared();
    if a <= EPSILON * EPSILON {
        return best;
    }
    for (x, sx) in [(min.x, -1.0), (max.x, 1.0)] {
        for (y, sy) in [(min.y, -1.0), (max.y, 1.0)] {
            let corner = Vec2::new(x, y);
            let offset = start - corner;
            let b = offset.dot(delta);
            let discriminant = b * b - a * (offset.length_squared() - radius * radius);
            if discriminant < 0.0 {
                continue;
            }
            let time = (-b - discriminant.sqrt()) / a;
            let normal = start + delta * time - corner;
            if normal.x * sx >= -EPSILON && normal.y * sy >= -EPSILON {
                offer_hit(&mut best, time, normal.normalize_or_zero(), delta);
            }
        }
    }
    best
}

pub fn move_circle(mut position: Vec2, mut delta: Vec2, radius: f32, map: &CollisionMap) -> Vec2 {
    let limit = map.half_size - radius;
    for _ in 0..8 {
        let length = delta.length();
        if length <= EPSILON {
            break;
        }
        let mut best = None;
        for axis in 0..2 {
            for (edge, sign) in [(-limit, 1.0), (limit, -1.0)] {
                if delta[axis].abs() > EPSILON {
                    let mut normal = Vec2::ZERO;
                    normal[axis] = sign;
                    offer_hit(
                        &mut best,
                        (edge - position[axis]) / delta[axis],
                        normal,
                        delta,
                    );
                }
            }
        }
        for obstacle in &map.movement {
            if let Some(hit) = sweep_circle(position, delta, radius, *obstacle) {
                offer_hit(&mut best, hit.time, hit.normal, delta);
            }
        }
        let Some(hit) = best else {
            position += delta;
            break;
        };
        position += delta * (hit.time - SKIN / length).max(0.0);
        delta *= 1.0 - hit.time;
        delta -= hit.normal * delta.dot(hit.normal).min(0.0);
    }
    position
}

/// Returns the first fraction along the segment, including a camera clearance margin.
pub fn segment_hit(from: Vec3, to: Vec3, bounds: Aabb, margin: f32) -> Option<f32> {
    let min = bounds.min - Vec3::splat(margin);
    let max = bounds.max + Vec3::splat(margin);
    let delta = to - from;
    let mut enter: f32 = 0.0;
    let mut exit: f32 = 1.0;
    for axis in 0..3 {
        if delta[axis].abs() <= EPSILON {
            if from[axis] < min[axis] || from[axis] > max[axis] {
                return None;
            }
        } else {
            let a = (min[axis] - from[axis]) / delta[axis];
            let b = (max[axis] - from[axis]) / delta[axis];
            enter = enter.max(a.min(b));
            exit = exit.min(a.max(b));
            if enter > exit {
                return None;
            }
        }
    }
    Some(enter)
}

pub fn camera_position(target: Vec3, desired: Vec3, margin: f32, map: &CollisionMap) -> Vec3 {
    let fraction = map
        .camera
        .iter()
        .filter_map(|bounds| segment_hit(target, desired, *bounds, margin))
        .fold(1.0_f32, f32::min);
    target.lerp(desired, fraction)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(obstacles: Vec<Aabb>) -> CollisionMap {
        CollisionMap {
            half_size: 80.0,
            camera: obstacles.clone(),
            movement: obstacles,
        }
    }

    fn wall() -> Aabb {
        Aabb::from_center_size(Vec3::new(0.0, 2.0, 0.0), Vec3::new(2.0, 4.0, 8.0))
    }

    #[test]
    fn large_move_cannot_tunnel_and_tangent_motion_slides() {
        let map = map(vec![wall()]);
        let stopped = move_circle(Vec2::new(-10.0, 0.0), Vec2::new(40.0, 0.0), 0.35, &map);
        assert!((stopped.x + 1.35).abs() < 0.001);
        let slid = move_circle(Vec2::new(-3.0, -2.0), Vec2::new(5.0, 3.0), 0.35, &map);
        assert!((slid.x + 1.35).abs() < 0.001);
        assert!((slid.y - 1.0).abs() < 0.001);
        assert!(!wall().overlaps_circle(slid, 0.35));
    }

    #[test]
    fn circle_uses_rounded_corners_and_can_move_away_from_contact() {
        let obstacle = Aabb {
            min: Vec3::ZERO,
            max: Vec3::ONE,
        };
        let map = map(vec![obstacle]);
        let end = move_circle(Vec2::splat(-2.0), Vec2::splat(1.6), 0.5, &map);
        assert!(end.distance(Vec2::splat(-0.4)) < 0.001);
        let contact = move_circle(Vec2::splat(-2.0), Vec2::splat(3.0), 0.5, &map);
        assert!((contact.length() - 0.5).abs() < 0.001);
        let away = move_circle(contact, Vec2::splat(-1.0), 0.5, &map);
        assert!(away.distance(contact + Vec2::splat(-1.0)) < 0.001);
    }

    #[test]
    fn boundary_accounts_for_radius_and_bridge_gap_is_passable() {
        let river = map(vec![
            Aabb::from_center_size(Vec3::new(0.0, 0.0, -7.0), Vec3::new(4.0, 1.0, 10.0)),
            Aabb::from_center_size(Vec3::new(0.0, 0.0, 7.0), Vec3::new(4.0, 1.0, 10.0)),
        ]);
        assert!(
            (move_circle(Vec2::new(-5.0, 0.0), Vec2::new(10.0, 0.0), 0.35, &river).x - 5.0).abs()
                < 0.001
        );
        assert!(move_circle(Vec2::new(-5.0, 4.0), Vec2::new(10.0, 0.0), 0.35, &river).x < -2.34);
        let bounded = move_circle(Vec2::ZERO, Vec2::new(400.0, 400.0), 0.35, &map(vec![]));
        assert!(bounded.x <= 79.65 && bounded.y <= 79.65);
        assert!(bounded.x > 79.64 && bounded.y > 79.64);
    }

    #[test]
    fn camera_stops_before_obstacle_and_recovers_when_unblocked() {
        let map = map(vec![wall()]);
        let target = Vec3::new(-4.0, 1.0, 0.0);
        let desired = Vec3::new(4.0, 1.0, 0.0);
        let close = camera_position(target, desired, 0.2, &map);
        assert!((close.x + 1.2).abs() < 0.001);
        let free = Vec3::new(-4.0, 3.0, 5.0);
        assert!(camera_position(target, free, 0.2, &map).distance(free) < 0.001);
    }
}
