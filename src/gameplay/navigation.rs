use std::{cmp::Reverse, collections::BinaryHeap};

use bevy::prelude::*;

use super::collision::{CollisionMap, move_circle};
use crate::data::SafeZone;

/// Two metre navigation cells; every edge is also checked by the production sweep.
pub struct NavGrid {
    size: usize,
    half: f32,
    free: Vec<bool>,
    radius: f32,
    safe: Option<SafeZone>,
}

pub fn crosses_safe_zone(from: Vec2, to: Vec2, zone: &SafeZone, radius: f32) -> bool {
    let center = Vec2::from_array(zone.center);
    let delta = to - from;
    let t = if delta.length_squared() > 0.0 {
        ((center - from).dot(delta) / delta.length_squared()).clamp(0.0, 1.0)
    } else {
        0.0
    };
    (from + delta * t).distance(center) < zone.radius + radius
}

impl NavGrid {
    pub fn new(map: &CollisionMap, safe: Option<&SafeZone>, radius: f32) -> Self {
        let size = map.half_size.ceil() as usize;
        let mut grid = Self {
            size,
            half: map.half_size,
            free: vec![false; size * size],
            radius,
            safe: safe.cloned(),
        };
        for i in 0..grid.free.len() {
            let p = grid.point(i);
            grid.free[i] = p.abs().max_element() + radius < map.half_size
                && !safe.is_some_and(|zone| crosses_safe_zone(p, p, zone, radius))
                && !map.movement.iter().any(|b| b.overlaps_circle(p, radius));
        }
        grid
    }

    fn point(&self, i: usize) -> Vec2 {
        Vec2::new(
            (i % self.size) as f32 * 2.0 + 1.0 - self.half,
            (i / self.size) as f32 * 2.0 + 1.0 - self.half,
        )
    }

    pub fn path(&self, from: Vec2, to: Vec2, map: &CollisionMap) -> Vec<Vec2> {
        let clear = |a: Vec2, b: Vec2| {
            !self
                .safe
                .as_ref()
                .is_some_and(|zone| crosses_safe_zone(a, b, zone, self.radius))
                && move_circle(a, b - a, self.radius, map).distance(b) < 0.001
        };
        if !to.is_finite()
            || to.abs().max_element() + self.radius >= map.half_size
            || map
                .movement
                .iter()
                .any(|b| b.overlaps_circle(to, self.radius))
        {
            return vec![];
        }
        if clear(from, to) {
            return vec![to];
        }
        let connector = |point: Vec2| {
            (0..self.free.len())
                .filter(|i| {
                    self.free[*i]
                        && self.point(*i).distance_squared(point) <= 16.0
                        && clear(point, self.point(*i))
                })
                .min_by(|a, b| {
                    self.point(*a)
                        .distance_squared(point)
                        .total_cmp(&self.point(*b).distance_squared(point))
                })
        };
        let Some(start) = connector(from) else {
            return vec![];
        };
        let Some(goal) = connector(to) else {
            return vec![];
        };
        let heuristic = |i: usize| (self.point(i).distance(to) * 10.0) as u32;
        let mut cost = vec![u32::MAX; self.free.len()];
        let mut parent = vec![usize::MAX; self.free.len()];
        let mut open = BinaryHeap::new();
        cost[start] = 0;
        open.push(Reverse((heuristic(start), 0_u32, start)));
        while let Some(Reverse((_, distance, i))) = open.pop() {
            if distance != cost[i] {
                continue;
            }
            if i == goal {
                let mut route = vec![to];
                let mut node = goal;
                while node != start {
                    route.push(self.point(node));
                    node = parent[node];
                }
                route.push(self.point(start));
                route.reverse();
                return route;
            }
            let x = (i % self.size) as i32;
            let y = (i / self.size) as i32;
            for (dx, dy) in [
                (-1, 0),
                (0, -1),
                (0, 1),
                (1, 0),
                (-1, -1),
                (-1, 1),
                (1, -1),
                (1, 1),
            ] {
                let (nx, ny) = (x + dx, y + dy);
                if nx < 0 || ny < 0 || nx >= self.size as i32 || ny >= self.size as i32 {
                    continue;
                }
                let next = ny as usize * self.size + nx as usize;
                if !self.free[next] || !clear(self.point(i), self.point(next)) {
                    continue;
                }
                let candidate = distance + if dx != 0 && dy != 0 { 28 } else { 20 };
                if candidate < cost[next] {
                    cost[next] = candidate;
                    parent[next] = i;
                    open.push(Reverse((candidate + heuristic(next), candidate, next)));
                }
            }
        }
        vec![]
    }
}
