# Documento normal

Un documento sin trucos, para ver que el arreglo del #5 no cambia nada visible. Texto con **negrita**, _cursiva_, ~~tachado~~, `código inline` y comillas "dobles" y 'simples' & ampersands < > sueltos.

- [Ir a la tabla](#tabla)
- [Link externo con title](https://example.com/una_ruta_con_guiones_bajos "Un title con comillas")
- [![badge](data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='90'%20height='20'%3E%3Crect%20width='90'%20height='20'%20rx='3'%20fill='%232da44e'/%3E%3C/svg%3E)](https://example.com/?a=1&b=2)

## Diagrama

```mermaid
graph LR
    A[archivo.md] --> B(MarkdownRenderer)
    B --> C{HTMLTemplate}
    C --> D[LectorMD.app]
    C --> E["Vista Rápida<br>sin red"]
```

## Código

```swift
func saludo(_ nombre: String) -> String {
    return "Hola, \(nombre)! <3 & chau"
}
```

## Tabla

| Elemento   | Soporte | Nota                 |
|------------|---------|----------------------|
| Headings   | ✓       | con `id` para anclas |
| Tablas     | ✓       | **negrita** en celda |
| Task lists | ✓       | [link](#fin)         |

- [x] Compilar sin Xcode
- [ ] Algo pendiente

> Una cita de bloque con _énfasis_.

## Imagen remota

![imagen remota](http://127.0.0.1:8765/legitima.png)

## Fin

Última línea.
